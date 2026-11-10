# frozen_string_literal: true

require_relative "fhir_query"
require_relative "profile_matcher"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    ItemUse = Data.define(:link_id, :text, :extension, :reads)

    # One form item, or the questionnaire root, reading a source through an expression of `extension`.
    # A use on the root has no `link_id` or `text`: the root's `text` is its narrative.
    class ItemUse
      VARIABLE = "variable"
      ROOT_LABEL = "The whole form"

      # What an item does with the source, by the extension whose expression reads it.
      ACTIONS = {
        "initialExpression" => "pre-fills the answer",
        "calculatedExpression" => "calculates the answer",
        "itemPopulationContext" => "sets the population context",
        "enableWhenExpression" => "shows or hides the item",
        "answerExpression" => "lists the answer options",
        "candidateExpression" => "suggests answers",
        "contextExpression" => "gives context for answering",
        "itemExtractionContext" => "sets the extraction context",
        "templateExtract" => "its answers fill the template"
      }.freeze
      private_constant :VARIABLE, :ROOT_LABEL, :ACTIONS

      # The use of an expression on `item`, the questionnaire root or an item, as a Hash.
      def self.of(item, extension, reads: [])
        item_text = item["text"]
        new(link_id: item["linkId"], text: (item_text if item_text.is_a?(String)), extension:, reads:)
      end

      # Whether the expression only defines a variable: the items that read the variable are what use the source.
      def self.variable?(extension)
        extension == VARIABLE
      end

      def initialize(link_id: nil, text: nil, extension: nil, reads: [])
        super
      end

      # The item's text with its Markdown escaped, else its linkId; a use with neither is on the questionnaire root.
      def label
        words = text.to_s.split.join(" ")
        return words.gsub(/[*_`\[\]]/) { |match| "\\#{match}" } unless words.empty?

        link_id&.to_s || ROOT_LABEL
      end

      # What the use does to the item, else the extension's name; `nil` without an extension.
      def action
        ACTIONS.fetch(extension) { extension }
      end
    end

    # One questionnaire source, shared by the groups whose profile it links to. Each kind is a subclass that
    # traces its sources (`.trace`) and says how it's shown and requested. Entries are equal only when they are
    # the same object, so equal sources in a form stay apart.
    class TraceEntry
      def initialize(**fields)
        @fields = fields
      end

      def name
        @fields[:name]
      end

      # The FhirQuery of a query or an `_include`, else `nil`.
      def query
        @fields[:query]
      end

      # A source no item uses is left out, unless a subclass says otherwise.
      def shown?
        item_uses.any?
      end

      def item_uses
        @fields[:item_uses].to_a
      end

      # The parameters of the search it makes, or `nil` when it makes no search.
      def search_params; end

      # `[kind, details]` lookups for `Generator::TestIndex#find`, which Delivery tries in order for the request
      # test; `resource` is the type of the entry's group.
      def request_lookups(_resource) = []

      # The type of the groups that hold its request test, or `nil` for the
      # group the entry was traced for.
      def request_type; end

      # The line a section shows for an entry with no item uses.
      def unused_line; end

      # Entries of one version of one form have the same key.
      def form_key
        @fields.values_at(:questionnaire_url, :questionnaire_id, :questionnaire_version)
      end

      def form_title
        @fields[:questionnaire_title] || @fields[:questionnaire_url] || @fields[:questionnaire_id] ||
          "Untitled questionnaire"
      end

      def form_version
        @fields[:questionnaire_version]
      end

      # A `launchContext` resource, like `%patient`.
      class LaunchContext < TraceEntry
        # `[groups, entry]` per type that has groups. `%name` is the resource itself, not a Bundle, and a chain that
        # picks one type, like `%user.where(resourceType = 'PractitionerRole')`, counts for that type only.
        def self.trace(form, launch_context, matcher)
          name = launch_context[:name]
          source = { name:, owner: launch_context[:owner], bundle: false }
          launch_context[:types].filter_map do |type|
            groups = matcher.match(type, any_of_type: true, context: "#{form.label} launch context #{name}")
            next unless groups

            item_uses = form.item_uses(source) { |chain_type| [nil, type].include?(chain_type) }
            [groups, new(**form.header, name:, item_uses:)]
          end
        end

        def request_lookups(_resource) = [["read", {}]]

        def heading(resource)
          "**Launch context #{name}**: the #{resource} the form is opened for"
        end
      end

      # An x-fhir-query variable: a search, or a read of one resource by id.
      class Query < TraceEntry
        # `[groups, entry]` for the query entry and each include entry of the form's x-fhir-query `variable`.
        def self.trace(form, variable, matcher, ig_resources)
          Variable.new(form, variable, ig_resources).entries(matcher)
        end

        # A variable's query entry, and an include entry per `_include` target type, which gets the chains that
        # pick that type, like `entry.resource.ofType(T)`. Included resources of the query's own type look like its
        # own, so their chains stay with the query entry.
        class Variable
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
            source = { name: @variable[:name], owner: @variable[:owner], bundle: !@query.read? }
            @form.item_uses(source, &)
          end

          def entry(kind, **fields)
            kind.new(**@form.header, name: @variable[:name], query: @query, **fields)
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
              QuestionnaireUsage.log("skipping #{name}=#{value} in #{label}: " \
                                     "only _include of #{resource_type} is traced")
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
        private_constant :Variable

        # A query that fetches other resources through `_include` is shown even
        # when no item reads its own results.
        def shown?
          super || includes.any?
        end

        # A search goes to the search test by the same parameters, in any order.
        def request_lookups(_resource)
          return [["read", {}]] if read?

          names = query.search_params
          names.empty? ? [] : [["search", { search_names: names }]]
        end

        def search_params
          query.search_params unless read?
        end

        def heading(resource)
          action = read? ? "reads one #{resource} by id" : "searches #{resource} resources"
          "**Query #{name}**: #{action}"
        end

        def unused_line
          "No item reads its results; it fetches #{includes.join(", ")} through _include"
        end

        private

        def read?
          query.read?
        end

        def includes
          query.includes
        end
      end

      # What a query fetches through one `_include` target. Its request is the
      # query's, so its test is in a group of the query's own type.
      class Include < TraceEntry
        # The include test for the entry's type, preferably the one that
        # searches by the same parameters.
        def request_lookups(resource)
          targets = [resource]
          [["include", { search_names: query.search_params, include_targets: targets }],
           ["include", { include_targets: targets }]]
        end

        def request_type
          query.resource_type
        end

        def heading(resource)
          "**Query #{name}**: fetches #{resource} resources through _include=#{@fields[:include]}"
        end
      end

      # A contained resource a `templateExtract` fills from the answers. It is
      # shown even when it is extracted from the whole form, which no item uses.
      class Template < TraceEntry
        # `[groups, entry]` for the form's `templateExtract` `extract`, when its template matches groups.
        def self.trace(form, extract, matcher)
          Extract.new(form, extract).entries(matcher)
        end

        # One `templateExtract` and its contained template. A PATCH template, with the smartforms
        # `TemplateExtractExtensionPatchRequestUrl` sub-extension, is a FHIRPath Patch `Parameters` resource: it
        # targets the type in its operations' `path`, else in its request URL, and fixes no codes.
        class Extract
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
            template_codes = codes.fetch(:code) { [] }.map do |coding|
              [coding[:system], coding[:code]].compact.join("|")
            end
            TraceEntry::Template.new(**@form.header, name: @template["id"] || @reference.delete_prefix("#"),
                                                     template_codes:, patch: patch?, item_uses:)
          end

          def patch_target
            paths = @template["parameter"].to_a.flat_map { |parameter| parameter["part"].to_a }
                                          .filter_map { |part| part["valueString"] if part["name"] == "path" }
            paths.first&.split(".")&.first || @patch_url[%r{\A\s*'([A-Za-z]+)/}, 1]
          end
        end
        private_constant :Extract

        def shown?
          true
        end

        # A FHIRPath Patch goes to the patch test, then the update test, not the
        # one that creates a new resource through update.
        def request_lookups(_resource)
          patch? ? [["patch", {}], ["update", { option: "update" }]] : [["create", {}]]
        end

        def heading(resource)
          "**Extraction template #{name}**: #{action(resource)}"
        end

        def unused_line
          "Its answers come from the whole form"
        end

        private

        def patch?
          @fields[:patch]
        end

        def action(resource)
          return "updates an existing #{resource} with a FHIRPath Patch" if patch?

          codes = @fields[:template_codes].to_a
          "creates a new #{resource}#{" with code #{codes.join(", ")}" unless codes.empty?} from the answers"
        end
      end
    end
  end
end
