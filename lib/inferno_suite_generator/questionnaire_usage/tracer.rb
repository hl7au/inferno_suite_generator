# frozen_string_literal: true

require_relative "ast"
require_relative "profile_matcher"
require_relative "sources"
require_relative "trace"
require_relative "trace_entry"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Traces every `Questionnaire` into a Trace. Each kind of source in `Sources` traces
    # its own entries; the Tracer walks the forms and resolves the aliases items read them through.
    class Tracer
      ASSEMBLE_CONTEXT_URL = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-assembleContext"

      def initialize(ig_resources, groups)
        @ig_resources = ig_resources
        @matcher = ProfileMatcher.new(groups, ig_resources)
      end

      def trace
        @ig_resources.get_resources_by_type("Questionnaire").each_with_object(Trace.new) do |questionnaire, trace|
          trace_form(trace, questionnaire.to_hash)
        end
      end

      private

      # Each kind of source gives `[groups, entry]` pairs, and the groups share the entry.
      def trace_form(trace, questionnaire)
        form = Form.new(questionnaire)
        log_assemble_contexts(form, questionnaire)
        entries(form).each { |groups, entry| trace.add(groups, entry) }
      end

      def entries(form)
        sources = form.query_variables.map { |variable| Sources::Query.new(form, variable, @ig_resources) } +
                  form.launch_contexts.map { |context| Sources::LaunchContext.new(form, context) } +
                  form.template_extracts.map { |extract| Sources::Template.new(form, extract) }
        sources.flat_map { |source| source.entries(@matcher) }
      end

      # A module form gets its `assembleContext` variables from the form it is
      # assembled into, so the items that read them are traced in the assembled form only.
      def log_assemble_contexts(form, questionnaire)
        names = Array(questionnaire["extension"]).filter_map do |extension|
          extension["valueString"] if extension["url"] == ASSEMBLE_CONTEXT_URL
        end
        return if names.empty?

        names &= references(form, questionnaire)
        return if names.empty?

        QuestionnaireUsage.log("#{form.label} reads #{names.join(", ")} from the form it is assembled " \
                               "into: trace the assembled form for their usages")
      end

      # The `%Name` names the expressions on the root and on items reference.
      def references(form, questionnaire)
        expressions = form.scope(questionnaire).flat_map { |owner| form.expressions(owner) }
        expressions.flat_map { |expression| form.fhirpath.references(expression[:expression]) }
      end

      # The items in a source's scope that read it, directly or through aliases: `text/fhirpath` variables reading
      # the source or another alias. Each alias starts where the chain defining it ends, as `Ast::ChainRead` gives.
      class ItemUses
        Name = Data.define(:name, :owner, :start)

        # `source` is `{ name:, owner:, start: }`, with `start:` an `Ast::Start`; `accept` takes a chain's type.
        def initialize(form, source, accept)
          @form = form
          @accept = accept
          @source = Name.new(**source)
          @names = [@source]
        end

        # The ItemUses, in document order.
        def call
          resolve_aliases
          @form.scope(@source.owner).flat_map { |owner| uses_on(owner) }.uniq
        end

        private

        # Repeats until no new alias is found. Each variable becomes an alias at
        # most once, so a form whose variables reference each other can't loop.
        def resolve_aliases
          pending = @form.fhirpath_variables.select { |variable| @form.covers?(@source.owner, variable[:owner]) }
          loop do
            break unless pending.reject! { |variable| add_alias(variable) }
          end
        end

        def add_alias(variable)
          read = reads_of(variable[:expression], variable[:owner]).first || mixed_read(variable)
          return false unless read

          @names << Name.new(name: variable[:name], owner: variable[:owner], start: read.alias_start)
          true
        end

        # A variable that picks several types, like `where(intent = 'order' or resourceType = 'Medication')`, reads
        # the source untyped, which `accept` may reject. It still becomes an alias, so typed chains from it count.
        def mixed_read(variable)
          return if @accept.call(nil)

          reads_of(variable[:expression], variable[:owner], accept: lambda(&:nil?)).find(&:resource?)
        end

        # One ItemUse per expression that reads the source, with the element
        # paths it reads. A variable is not an item use: the items that read it are.
        def uses_on(item)
          @form.expressions(item).filter_map do |expression|
            extension = expression[:extension]
            next if ItemUse.variable?(extension)

            reads = reads_of(expression[:expression], item)
            next if reads.empty?

            ItemUse.of(item, extension, reads: reads.flat_map(&:paths).uniq)
          end
        end

        def reads_of(expression, node, accept: @accept)
          @names.select { |name| @form.covers?(name.owner, node) }
                .flat_map { |name| @form.fhirpath.reads(expression, name.name, from: name.start) }
                .select { |read| accept.call(read.type) }
        end
      end

      # A questionnaire as a Hash, with the walks the tracer needs. The root and
      # the items that can define variables are its "owners".
      class Form
        VARIABLE_URL = "http://hl7.org/fhir/StructureDefinition/variable"
        LAUNCH_CONTEXT_URL = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-launchContext"
        TEMPLATE_EXTRACT_URL = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-templateExtract"
        FHIRPATH = "text/fhirpath"
        QUERY = "application/x-fhir-query"

        def initialize(questionnaire)
          @questionnaire = questionnaire
        end

        # The form's parsed FHIRPath, shared by every source traced in it.
        def fhirpath = (@fhirpath ||= Ast::Cache.new)

        # The `id` stands in for a missing `url`, so forms without one stay apart.
        def header
          url = @questionnaire["url"]
          FormHeader.new(url:, id: (@questionnaire["id"] unless url), version: @questionnaire["version"],
                         title: @questionnaire["title"])
        end

        def label
          @questionnaire["title"] || @questionnaire["url"] || @questionnaire["id"]
        end

        # The x-fhir-query `variable` extensions on the root and on items, in document order.
        def query_variables
          variables_in(QUERY)
        end

        # `{ name:, types:, owner: }` for each root `launchContext`. The name is in `valueCoding.code`, or in
        # `valueId` in older SDC versions; each `type` sub-extension adds a type.
        def launch_contexts
          list(@questionnaire["extension"]).select { |extension| extension["url"] == LAUNCH_CONTEXT_URL }
                                           .filter_map { |extension| launch_context(list(extension["extension"])) }
        end

        # `{ extension:, owner:, defined_at: }` for each `templateExtract` on the root and on items, in document order.
        def template_extracts
          owners.flat_map do |owner|
            list(owner["extension"]).select { |extension| extension["url"] == TEMPLATE_EXTRACT_URL }
                                    .map { |extension| { extension:, owner:, defined_at: defined_at(owner) } }
          end
        end

        # The ItemUses of `source`, `{ name:, owner:, start: }`, for the chains whose type the block takes.
        def item_uses(source, &accept)
          ItemUses.new(self, source, accept).call
        end

        # The contained resource with this `id`, or `nil`.
        def contained(id)
          list(@questionnaire["contained"]).find { |resource| resource["id"] == id }
        end

        def root?(owner)
          owner.equal?(@questionnaire)
        end

        # The `text/fhirpath` `variable` extensions, in document order.
        def fhirpath_variables
          @fhirpath_variables ||= variables_in(FHIRPATH)
        end

        # The owner and the items under it: the root and every item for a root
        # variable, the item and its children for an item variable.
        def scope(owner)
          [owner, *descendants(owner)]
        end

        # Whether a variable defined on `owner`, the root or an item, is visible at `node`.
        def covers?(owner, node)
          return true if owner.equal?(@questionnaire)

          node = parents[node] until node.nil? || node.equal?(owner)
          !node.nil?
        end

        # `{ extension:, expression: }` for each `text/fhirpath` expression in the item's own extensions and
        # their sub-extensions, not in nested items. `extension` is the short name, like `initialExpression`.
        def expressions(item)
          list(item["extension"]).flat_map { |extension| extension_expressions(extension, short_name(extension)) }
        end

        private

        def extension_expressions(extension, name)
          value = extension["valueExpression"]
          own = value && value["language"] == FHIRPATH && value["expression"] ? [value["expression"]] : []
          own.map { |expression| { extension: name, expression: } } +
            list(extension["extension"]).flat_map { |sub_extension| extension_expressions(sub_extension, name) }
        end

        def short_name(extension)
          extension["url"].to_s.split("/").last.to_s.delete_prefix("sdc-questionnaire-")
        end

        def launch_context(parts)
          name_part = parts.find { |part| part["url"] == "name" } || {}
          name = name_part.dig("valueCoding", "code") || name_part["valueId"]
          types = parts.select { |part| part["url"] == "type" }.filter_map { |part| part["valueCode"] }
          { name:, types:, owner: @questionnaire } if name
        end

        def variables_in(language)
          owners.flat_map do |owner|
            variables(owner).select { |expression| expression["language"] == language }.map do |expression|
              { name: expression["name"], expression: expression["expression"].to_s, owner: }
            end
          end
        end

        def variables(owner)
          list(owner["extension"]).select { |extension| extension["url"] == VARIABLE_URL }
                                  .filter_map { |extension| extension["valueExpression"] }
        end

        def parents
          @parents ||= owners.each_with_object({}.compare_by_identity) do |node, map|
            list(node["item"]).each { |child| map[child] = node }
          end
        end

        def defined_at(owner)
          owner.equal?(@questionnaire) ? "root" : owner["linkId"]
        end

        # The root and every item, in document order.
        def owners
          [@questionnaire, *descendants(@questionnaire)]
        end

        def descendants(node)
          list(node["item"]).flat_map { |item| [item, *descendants(item)] }
        end

        def list(value)
          value.is_a?(Array) ? value : []
        end
      end
    end
  end
end
