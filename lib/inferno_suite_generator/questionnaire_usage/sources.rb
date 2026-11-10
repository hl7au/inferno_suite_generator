# frozen_string_literal: true

require_relative "ast"
require_relative "fhir_query"
require_relative "profile_matcher"
require_relative "trace_entry"

module InfernoSuiteGenerator
  module QuestionnaireUsage
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

        # A pair per type that has groups.
        def entries(matcher)
          name = @launch_context[:name]
          source = { name:, owner: @launch_context[:owner], start: Ast::Start.resource }
          @launch_context[:types].filter_map do |type|
            groups = matcher.match(type, any_of_type: true, context: "#{@form.label} launch context #{name}")
            next unless groups

            item_uses = @form.item_uses(source) { |chain_type| [nil, type].include?(chain_type) }
            [groups, TraceEntry::LaunchContext.new(form: @form.header, name:, item_uses:)]
          end
        end
      end

      # An x-fhir-query `variable`: its query entry, and an include entry per `_include` target type, which gets
      # the chains that pick that type, like `entry.resource.ofType(T)`. Included resources of the query's own
      # type look like its own, so their chains stay with the query entry.
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

        # The uses of the chains whose type the block takes; a read's `%Name` is one resource, not a Bundle.
        def item_uses(&)
          start = @query.read? ? Ast::Start.resource : Ast::Start.bundle
          @form.item_uses({ name: @variable[:name], owner: @variable[:owner], start: }, &)
        end

        def entry(kind, **fields)
          kind.new(form: @form.header, name: @variable[:name], query: @query, **fields)
        end

        # `{ value:, target: }` per target type of each own-type `_include`: the explicit `Source:param:Target`,
        # else the SearchParameter's targets, else the types the form picks with `ofType(T)` or `resourceType = 'T'`.
        def include_targets
          @include_targets ||= include_values.flat_map { |value| targets_of(value) }
        end

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
          expressions.flat_map { |expression| @form.fhirpath.reads(expression, name, from: Ast::Start.bundle) }
                     .flat_map(&:types).uniq - [resource_type]
        end

        # Variables are `variable` extensions, so the owners' expressions
        # include them.
        def expressions
          @form.scope(@variable[:owner]).flat_map do |owner|
            @form.expressions(owner).map { |expression| expression[:expression] }
          end
        end
      end

      # One `templateExtract` and its contained template. A PATCH template, with the smartforms
      # `TemplateExtractExtensionPatchRequestUrl` sub-extension, is a FHIRPath Patch `Parameters` resource: it
      # targets the type in its operations' `path`, else in its request URL, and fixes no codes.
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

        # One pair when the template matches groups.
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
          template_codes = codes.fetch(:code) { [] }.map do |coding|
            [coding[:system], coding[:code]].compact.join("|")
          end
          TraceEntry::Template.new(form: @form.header, name: @template["id"] || @reference.delete_prefix("#"),
                                   template_codes:, patch: patch?, item_uses:)
        end

        def patch_target
          paths = @template["parameter"].to_a.flat_map { |parameter| parameter["part"].to_a }
                                        .filter_map { |part| part["valueString"] if part["name"] == "path" }
          paths.first&.split(".")&.first || @patch_url[%r{\A\s*'([A-Za-z]+)/}, 1]
        end
      end
    end
  end
end
