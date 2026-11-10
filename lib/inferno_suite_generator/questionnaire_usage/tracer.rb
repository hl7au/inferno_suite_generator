# frozen_string_literal: true

require_relative "ast"
require_relative "fhir_query"
require_relative "item_use"
require_relative "log"
require_relative "profile_matcher"
require_relative "trace_entry"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Finds the questionnaire sources that link to each profile in the suite and
    # the items that use them.
    #
    # `trace` returns `{ profile_url => [TraceEntry] }`. Every `Questionnaire` in
    # `ig_resources` is traced.
    class Tracer
      ASSEMBLE_CONTEXT_URL = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-assembleContext"

      def initialize(ig_resources, groups)
        @ig_resources = ig_resources
        @matcher = ProfileMatcher.new(groups, ig_resources)
      end

      def trace
        traces = {}
        @ig_resources.get_resources_by_type("Questionnaire").each do |questionnaire|
          trace_form(traces, questionnaire.to_hash)
        end
        traces
      end

      private

      # Each source gives `[groups, entry]` pairs, and the groups share the entry.
      def trace_form(traces, questionnaire)
        form = Form.new(questionnaire)
        log_assemble_contexts(form, questionnaire)
        sources(form).flat_map { |source| source.entries(@matcher) }.each do |groups, entry|
          groups.each { |group| (traces[group.profile_url] ||= []) << entry }
        end
      end

      def sources(form)
        form.query_variables.map { |variable| Query.new(form, variable, @ig_resources) } +
          form.launch_contexts.map { |launch_context| LaunchContext.new(form, launch_context) } +
          form.template_extracts.map { |extract| Template.new(form, extract) }
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

      # One x-fhir-query variable of a form: a `query` entry for its own type
      # and an `include` entry for each `_include` target type. Chains are
      # routed by type: one that picks an included type, with
      # `entry.resource.ofType(T)` or `entry.where(resource is T)`, goes to
      # that include entry, anything else to the query entry.
      #
      # An included resource of the query's own type can't be told apart from
      # the query's own resources by type, so chains of that type stay with the
      # query entry, and its include entry has no item uses.
      class Query
        def initialize(form, variable, ig_resources)
          @form = form
          @variable = variable
          @ig_resources = ig_resources
          @query = FhirQuery.new(variable[:expression])
        end

        def entries(matcher)
          [query_entry(matcher), *include_targets.map { |include| include_entry(matcher, include) }].compact
        end

        private

        def label
          "#{@form.label} query #{@variable[:name]}"
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
          target = include[:target]
          groups = matcher.match(target, any_of_type: true, context: "#{label} include #{include[:value]}")
          return unless groups

          uses = target == resource_type ? [] : item_uses { |type| type == target }
          [groups, entry(TraceEntry::Include, include: include[:value], item_uses: uses)]
        end

        # The item uses of the chains whose type the block takes. A read gives
        # one resource, so its `%Name` is that resource, not a Bundle.
        def item_uses(&accept)
          source = { name: @variable[:name], owner: @variable[:owner], bundle: !@query.read? }
          ItemUses.new(@form, source, accept).call
        end

        # A trace entry of this kind: the fields shared by query and include
        # entries, then `fields`.
        def entry(kind, **fields)
          kind.new(**@form.header, name: @variable[:name], query: @query, **fields)
        end

        # `{ value:, target: }` for each target type of each
        # `_include` of the query's own type. The target is the explicit
        # `Source:param:Target`, else the SearchParameter's `target` list, else
        # the types the form picks out with `entry.resource.ofType(T)` or
        # `entry.resource.where(resourceType = 'T')`.
        def include_targets
          @include_targets ||= include_values.flat_map { |value| targets_of(value) }
        end

        # The `_include` target types other than the query's own.
        def other_include_types
          include_targets.map { |include| include[:target] } - [resource_type]
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
          targets.map { |target| { value:, target: } }
        end

        def implied_targets(source, param)
          from_param = Array(@ig_resources.search_param_by_resource_and_code(source, param)&.target)
          from_param.any? ? from_param : of_types
        end

        # The types other than the query's own that the form names on
        # `%Name.entry` or `%Name.entry.resource`, in the query's scope.
        def of_types
          name = @variable[:name]
          fhirpath = @form.fhirpath
          expressions.select { |expression| fhirpath.references(expression).include?(name) }
                     .flat_map { |expression| fhirpath.paths(expression, name, bundle: true) }
                     .flat_map { |chain| chain[:types] }.uniq - [resource_type]
        end

        # Variables are `variable` extensions, so the owners' expressions
        # include them.
        def expressions
          @form.scope(@variable[:owner]).flat_map do |owner|
            @form.expressions(owner).map { |expression| expression[:expression] }
          end
        end
      end

      # One `launchContext` extension, with one entry per type that has
      # groups. `%name` is the resource itself, not a Bundle. A chain that
      # picks one type, like `%user.where(resourceType = 'PractitionerRole')`,
      # counts for that type only.
      class LaunchContext
        def initialize(form, launch_context)
          @form = form
          @launch_context = launch_context
        end

        def entries(matcher)
          name = @launch_context[:name]
          @launch_context[:types].filter_map do |type|
            groups = matcher.match(type, any_of_type: true, context: "#{@form.label} launch context #{name}")
            [groups, entry(type)] if groups
          end
        end

        private

        def entry(type)
          name = @launch_context[:name]
          source = { name:, owner: @launch_context[:owner], bundle: false }
          item_uses = ItemUses.new(@form, source, ->(chain_type) { [nil, type].include?(chain_type) }).call
          TraceEntry::LaunchContext.new(**@form.header, name:, item_uses:)
        end
      end

      # One `templateExtract` extension and the contained template it points to.
      #
      # A PATCH template (with the smartforms `TemplateExtractExtensionPatchRequestUrl`
      # sub-extension) is a FHIRPath Patch `Parameters` resource. Its target type
      # comes from the operations' `path`, or else from the request URL, like
      # `'Condition/' + ...`. It fixes no codes.
      class Template
        PATCH_URL_SUFFIX = "/TemplateExtractExtensionPatchRequestUrl"

        def initialize(form, extract)
          @form = form
          @extract = extract
          parts = extract[:extension]["extension"].to_a
          @reference = parts.find { |part| part["url"] == "template" }&.dig("valueReference", "reference").to_s
          @patch_url = parts.find { |part| part["url"].to_s.end_with?(PATCH_URL_SUFFIX) }&.dig("valueString")
          @template = form.contained(@reference.delete_prefix("#"))
        end

        def entries(matcher)
          label = "#{@form.label} templateExtract #{@reference} on #{@extract[:defined_at]}"
          unless @template
            QuestionnaireUsage.log("skipping #{label}: no contained resource #{@reference}")
            return []
          end

          groups = matcher.match(resource_type, codes:, context: label)
          groups ? [[groups, entry]] : []
        end

        private

        def patch?
          !@patch_url.nil?
        end

        def resource_type
          patch? ? patch_target : @template["resourceType"]
        end

        def codes
          patch? ? {} : ProfileMatcher::Codes.from_template(@template)
        end

        def entry
          owner = @extract[:owner]
          item_uses = @form.root?(owner) ? [] : [ItemUse.of(owner, "templateExtract")]
          template_codes = codes.fetch(:code) { [] }.map { |coding| [coding[:system], coding[:code]].compact.join("|") }
          TraceEntry::Template.new(**@form.header, name: @template["id"] || @reference.delete_prefix("#"),
                                                   template_codes:, patch: patch?, item_uses:)
        end

        def patch_target
          paths = @template["parameter"].to_a.flat_map { |parameter| parameter["part"].to_a }
                                        .filter_map { |part| part["valueString"] if part["name"] == "path" }
          paths.first&.split(".")&.first || @patch_url[%r{\A\s*'([A-Za-z]+)/}, 1]
        end
      end

      # The item uses of one source in one form: the items in its scope that read
      # it, directly or through aliases, and the element paths they read.
      #
      # An alias is a `text/fhirpath` variable whose expression reads the source
      # or another alias. Its prefix is the parent's prefix plus the path of its
      # own chain, or `nil` when that chain stopped (see `Ast::ChainPath`). It
      # keeps the chain's type, and only chains whose type `accept` takes count.
      # A chain's own type counts only on a name that is a resource, or Bundle
      # entries, with the prefix `""`. An alias of a chain that ends at Bundle
      # entries, like `%q.entry.where(resource is Condition)`, is entries too.
      class ItemUses
        Name = Struct.new(:name, :owner, :bundle, :type, :prefix, keyword_init: true)

        # `source` is `{ name:, owner:, bundle: }`. `bundle: true` for a query,
        # whose `%Name` is a Bundle. `Ast::ChainPath` lists the values.
        def initialize(form, source, accept)
          @form = form
          @accept = accept
          @source = Name.new(**source, type: nil, prefix: "")
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
          reads = reads_of(variable[:expression], variable[:owner])
          return add_mixed_alias(variable) if reads.empty?

          name, chain = reads.first
          add_name(variable, chain, type: type_of(name, chain), prefix: chain[:stopped] ? nil : read_path(name, chain))
        end

        # A variable that picks resources of several types, like
        # `%q.entry.resource.where(intent = 'order' or resourceType = 'Medication')`,
        # reads the source through an untyped chain that `accept` may reject.
        # It still becomes an alias, with no paths of its own, so a typed chain
        # from it, like `%name.where(resourceType = 'Medication')`, counts.
        def add_mixed_alias(variable)
          return false if @accept.call(nil)

          untyped = reads_of(variable[:expression], variable[:owner], accept: lambda(&:nil?))
          _name, chain = untyped.find { |name, read| resource?(name, read) }
          return false unless chain

          add_name(variable, chain, type: nil, prefix: "")
        end

        def add_name(variable, chain, type:, prefix:)
          @names << Name.new(name: variable[:name], owner: variable[:owner], bundle: chain[:entries] ? :entries : false,
                             type:, prefix:)
          true
        end

        def resource?(name, chain)
          name.prefix == "" && chain[:path].empty? && !chain[:stopped]
        end

        # One ItemUse per expression that reads the source, with the element
        # paths it reads. A variable is not an item use: the items that read it are.
        def uses_on(item)
          @form.expressions(item).filter_map do |expression|
            extension = expression[:extension]
            next if ItemUse.variable?(extension)

            reads = reads_of(expression[:expression], item)
            next if reads.empty?

            ItemUse.of(item, extension, reads: reads.flat_map { |read| read_paths(*read) }.reject(&:empty?).uniq)
          end
        end

        # `[name, chain]` for each accepted chain in the expression from a name
        # visible at `node`.
        def reads_of(expression, node, accept: @accept)
          references = @form.fhirpath.references(expression)
          @names.select { |name| references.include?(name.name) && @form.covers?(name.owner, node) }
                .flat_map do |name|
            @form.fhirpath.paths(expression, name.name, bundle: name.bundle)
                 .filter_map { |chain| [name, chain] if accept.call(type_of(name, chain)) }
          end
        end

        def type_of(name, chain)
          name.type || (chain[:type] if name.prefix == "")
        end

        def read_path(name, chain)
          [name.prefix, chain[:path]].reject(&:empty?).join(".") if name.prefix
        end

        # The chain's path and the paths its criteria read, after the prefix.
        # None when the prefix is unknown.
        def read_paths(name, chain)
          return [] unless name.prefix

          [chain[:path], *chain[:criteria]].map { |path| [name.prefix, path].reject(&:empty?).join(".") }
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
          { questionnaire_url: url, questionnaire_id: (@questionnaire["id"] unless url),
            questionnaire_version: @questionnaire["version"], questionnaire_title: @questionnaire["title"] }.compact
        end

        def label
          @questionnaire["title"] || @questionnaire["url"] || @questionnaire["id"]
        end

        # The x-fhir-query `variable` extensions on the root and on items, in
        # document order.
        def query_variables
          variables_in(QUERY)
        end

        # `{ name:, types:, owner: }` for each `launchContext`
        # extension on the root. The name is in `valueCoding.code`, or in
        # `valueId` in older SDC versions. Each `type` sub-extension adds a type.
        def launch_contexts
          list(@questionnaire["extension"]).select { |extension| extension["url"] == LAUNCH_CONTEXT_URL }
                                           .filter_map { |extension| launch_context(list(extension["extension"])) }
        end

        # `{ extension:, owner:, defined_at: }` for each `templateExtract`
        # extension on the root and on items, in document order.
        def template_extracts
          owners.flat_map do |owner|
            list(owner["extension"]).select { |extension| extension["url"] == TEMPLATE_EXTRACT_URL }
                                    .map { |extension| { extension:, owner:, defined_at: defined_at(owner) } }
          end
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

        # Whether a variable defined on `owner` (the root or an item) is visible
        # at `node`.
        def covers?(owner, node)
          return true if owner.equal?(@questionnaire)

          node = parents[node] until node.nil? || node.equal?(owner)
          !node.nil?
        end

        # `{ extension:, expression: }` for each `text/fhirpath` expression in
        # the item's own extensions and their sub-extensions. Nested items are
        # not read. `extension` is the short name, like `initialExpression`.
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
