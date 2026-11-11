# frozen_string_literal: true

require_relative "ast"
require_relative "profile_matcher"
require_relative "trace"

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
                               "into: trace the assembled form for their item uses")
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

        # The ItemUses of the source `name` defined on `owner`, read from `start`, an `Ast::Start`, for the chains
        # whose type the block takes.
        def self.call(form, name:, owner:, start:, &accept)
          new(form, Name.new(name:, owner:, start:), accept).call
        end

        def initialize(form, source, accept)
          @form = form
          @accept = accept
          @source = source
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
          pending = @form.fhirpath_variables.select { |variable| @form.covers?(@source.owner, variable.owner) }
          loop do
            break unless pending.reject! { |variable| add_alias(variable) }
          end
        end

        def add_alias(variable)
          read = reads_of(variable.expression, variable.owner).first || mixed_read(variable)
          return false unless read

          @names << Name.new(name: variable.name, owner: variable.owner, start: read.alias_start)
          true
        end

        # A variable that picks several types, like `where(intent = 'order' or resourceType = 'Medication')`, reads
        # the source untyped, which `accept` may reject. It still becomes an alias, so typed chains from it count.
        def mixed_read(variable)
          return if @accept.call(nil)

          reads_of(variable.expression, variable.owner, accept: lambda(&:nil?)).find(&:resource?)
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
        PATCH_URL_SUFFIX = "/TemplateExtractExtensionPatchRequestUrl"
        FHIRPATH = "text/fhirpath"
        QUERY = "application/x-fhir-query"

        # A `variable` extension, on the root or an item: its `owner`.
        Variable = Data.define(:name, :expression, :owner)
        # A root `launchContext`, which may be any of its types.
        LaunchContext = Data.define(:name, :types, :owner)
        # A `templateExtract` extension on `owner`: the `reference` to its contained `template`, `nil` when the
        # form has none, and the smartforms PATCH request URL, if any. `defined_at` is `root` or the owner's linkId.
        TemplateExtract = Data.define(:reference, :template, :patch_url, :owner, :defined_at)

        def initialize(questionnaire)
          @questionnaire = questionnaire
        end

        # The form's parsed FHIRPath, shared by every source traced in it.
        def fhirpath = (@fhirpath ||= Ast::Cache.new)

        # The `id` stands in for a missing `url`, so forms without one stay apart.
        def header
          url = @questionnaire["url"]
          @header ||= FormHeader.new(url:, id: (@questionnaire["id"] unless url), version: @questionnaire["version"],
                                     title: @questionnaire["title"])
        end

        def label = header.label

        # The x-fhir-query `variable` extensions on the root and on items, in document order.
        def query_variables
          variables_in(QUERY)
        end

        # The root's LaunchContexts. The name is in `valueCoding.code`, or in `valueId` in older SDC versions; each
        # `type` sub-extension adds a type.
        def launch_contexts
          list(@questionnaire["extension"]).select { |extension| extension["url"] == LAUNCH_CONTEXT_URL }
                                           .filter_map { |extension| launch_context(list(extension["extension"])) }
        end

        # The TemplateExtracts on the root and on items, in document order.
        def template_extracts
          owners.flat_map do |owner|
            list(owner["extension"]).select { |extension| extension["url"] == TEMPLATE_EXTRACT_URL }
                                    .map { |extension| template_extract(list(extension["extension"]), owner) }
          end
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
          return true if root?(owner)

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

        def template_extract(parts, owner)
          reference = parts.find { |part| part["url"] == "template" }&.dig("valueReference", "reference").to_s
          patch_url = parts.find { |part| part["url"].to_s.end_with?(PATCH_URL_SUFFIX) }&.dig("valueString")
          TemplateExtract.new(reference:, template: contained(reference.delete_prefix("#")), patch_url:, owner:,
                              defined_at: root?(owner) ? "root" : owner["linkId"])
        end

        def contained(id)
          list(@questionnaire["contained"]).find { |resource| resource["id"] == id }
        end

        def launch_context(parts)
          name_part = parts.find { |part| part["url"] == "name" } || {}
          name = name_part.dig("valueCoding", "code") || name_part["valueId"]
          types = parts.select { |part| part["url"] == "type" }.filter_map { |part| part["valueCode"] }
          LaunchContext.new(name, types, @questionnaire) if name
        end

        def variables_in(language)
          owners.flat_map do |owner|
            variables(owner).select { |expression| expression["language"] == language }.map do |expression|
              Variable.new(name: expression["name"], expression: expression["expression"].to_s, owner:)
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

    # The kinds of questionnaire source Tracer traces. Each traces one source of a form with `entries(matcher)`,
    # into `[groups, entry]` pairs whose groups share the entry.
    module Sources
      # A `launchContext` resource, like `%patient`. `%name` is the resource itself, not a Bundle, and a chain
      # that picks one type, like `%user.where(resourceType = 'PractitionerRole')`, counts for that type only.
      class LaunchContext
        def initialize(form, launch_context)
          @form = form
          @launch_context = launch_context
        end

        def entries(matcher)
          name = @launch_context.name
          owner = @launch_context.owner
          @launch_context.types.filter_map do |type|
            groups = matcher.match(type, any_of_type: true, context: "#{@form.label} launch context #{name}")
            next unless groups

            item_uses = Tracer::ItemUses.call(@form, name:, owner:, start: Ast::Start.resource) do |chain_type|
              [nil, type].include?(chain_type)
            end
            [groups, TraceEntry::LaunchContext.new(header: @form.header, name:, item_uses:)]
          end
        end
      end

      # An x-fhir-query `variable`: its query entry, and an include entry per `_include` target type, which gets
      # the chains that pick that type, like `entry.resource.ofType(T)`. Included resources of the query's own
      # type look like its own, so their chains stay with the query entry.
      class Query
        # One target type of an `_include` value.
        IncludeTarget = Data.define(:value, :target)

        def initialize(form, variable, ig_resources)
          @form = form
          @variable = variable
          @ig_resources = ig_resources
          @query = FhirQuery.new(variable.expression)
        end

        def entries(matcher)
          [query_entry(matcher), *include_targets.map { |include| include_entry(matcher, include) }].compact
        end

        private

        def label
          "#{@form.label} query #{@variable.name}"
        end

        def resource_type
          @query.resource_type
        end

        # A read, like `Patient/{{%patient.id}}`, has no codes to tell profiles
        # apart, so it links to every group of its type, like a launch context.
        def query_entry(matcher)
          groups = matcher.match(resource_type, codes: @query.codes, any_of_type: @query.read?, context: label)
          return unless groups

          others = other_include_types
          [groups, entry(TraceEntry::Query, item_uses: item_uses { |type| !others.include?(type) })]
        end

        def include_entry(matcher, include)
          target = include.target
          groups = matcher.match(target, any_of_type: true, context: "#{label} include #{include.value}")
          return unless groups

          uses = target == resource_type ? [] : item_uses { |type| type == target }
          [groups, entry(TraceEntry::Include, include: include.value, item_uses: uses)]
        end

        # A read's `%Name` is one resource, not a Bundle.
        def item_uses(&)
          start = @query.read? ? Ast::Start.resource : Ast::Start.bundle
          Tracer::ItemUses.call(@form, name: @variable.name, owner: @variable.owner, start:, &)
        end

        def entry(kind, **fields)
          kind.new(header: @form.header, name: @variable.name, query: @query, **fields)
        end

        # An IncludeTarget per target type of each own-type `_include`: the explicit `Source:param:Target`,
        # else the SearchParameter's targets, else the types the form picks with `ofType(T)` or `resourceType = 'T'`.
        def include_targets
          @include_targets ||= include_values.flat_map { |value| targets_of(value) }
        end

        def other_include_types
          include_targets.map(&:target) - [resource_type]
        end

        def include_values
          @query.other_includes.each do |name, value|
            QuestionnaireUsage.log("skipping #{name}=#{value} in #{label}: only _include of #{resource_type} is traced")
          end
          @query.includes
        end

        def targets_of(value)
          source, param, explicit = value.split(":", 3)
          targets = explicit ? [explicit] : implied_targets(source, param)
          QuestionnaireUsage.log("unresolved #{label} include #{value}: no target type") if targets.empty?
          targets.map { |target| IncludeTarget.new(value:, target:) }
        end

        def implied_targets(source, param)
          from_param = Array(@ig_resources.search_param_by_resource_and_code(source, param)&.target)
          from_param.any? ? from_param : of_types
        end

        # The types other than the query's own that the form names on
        # `%Name.entry` or `%Name.entry.resource`, in the query's scope.
        def of_types
          name = @variable.name
          expressions.flat_map { |expression| @form.fhirpath.reads(expression, name, from: Ast::Start.bundle) }
                     .flat_map(&:types).uniq - [resource_type]
        end

        # Variables are `variable` extensions, so the owners' expressions
        # include them.
        def expressions
          @form.scope(@variable.owner).flat_map do |owner|
            @form.expressions(owner).map { |expression| expression[:expression] }
          end
        end
      end

      # One `templateExtract` and its contained template. A PATCH template, with the smartforms
      # `TemplateExtractExtensionPatchRequestUrl` sub-extension, is a FHIRPath Patch `Parameters` resource: it
      # targets the type in its operations' `path`, else in its request URL, and fixes no codes.
      class Template
        def initialize(form, extract)
          @form = form
          @extract = extract
          @template = extract.template
        end

        def entries(matcher)
          reference = @extract.reference
          label = "#{@form.label} templateExtract #{reference} on #{@extract.defined_at}"
          unless @template
            QuestionnaireUsage.log("skipping #{label}: no contained resource #{reference}")
            return []
          end

          groups = matcher.match(resource_type, codes:, context: label)
          groups ? [[groups, entry]] : []
        end

        private

        def patch?
          !@extract.patch_url.nil?
        end

        def resource_type
          patch? ? patch_target : @template["resourceType"]
        end

        def codes
          patch? ? {} : ProfileMatcher::Codes.from_template(@template)
        end

        def entry
          owner = @extract.owner
          item_uses = @form.root?(owner) ? [] : [ItemUse.of(owner, "templateExtract")]
          template_codes = codes.fetch(:code) { [] }.map do |coding|
            [coding[:system], coding[:code]].compact.join("|")
          end
          TraceEntry::Template.new(header: @form.header, name: @template["id"],
                                   template_codes:, patch: patch?, item_uses:)
        end

        def patch_target
          paths = @template["parameter"].to_a.flat_map { |parameter| parameter["part"].to_a }
                                        .filter_map { |part| part["valueString"] if part["name"] == "path" }
          paths.first&.split(".")&.first || @extract.patch_url[%r{\A\s*'([A-Za-z]+)/}, 1]
        end
      end
    end
  end
end
