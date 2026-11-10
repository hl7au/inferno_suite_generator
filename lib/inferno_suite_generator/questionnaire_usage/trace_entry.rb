# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # One questionnaire source traced for the groups whose profile it links to.
    # Each kind of source is a subclass, which says whether the entry is shown,
    # how to find the test that makes its request and how a section names it,
    # so a new kind is one new class.
    #
    # Groups that share a source share its entry, and two entries are the same
    # only if they are the same object, so equal sources in a form stay apart.
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

      # The ItemUses sections list.
      def item_uses
        @fields[:item_uses].to_a
      end

      # The parameters of the search it makes, or `nil` when it makes no search.
      def search_params; end

      # How Delivery finds its request test: `[kind, details]` lookups for
      # `Generator::TestIndex#find`, tried in order. `resource` is the type of
      # the group the entry was traced for.
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
        def request_lookups(_resource) = [["read", {}]]

        def heading(resource)
          "**Launch context #{name}**: the #{resource} the form is opened for"
        end
      end

      # An x-fhir-query variable: a search, or a read of one resource by id.
      class Query < TraceEntry
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
