# frozen_string_literal: true

require_relative "query_search"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # One questionnaire source traced for the groups whose profile it links to.
    # Each kind of source is a subclass, which says whether the entry is shown,
    # which test makes its request and how a section names it, so a new kind
    # is one new class.
    #
    # The `Tracer` builds entries from the fields of the trace file. Groups that
    # share a source share its entry, and two entries are the same only if they
    # are the same object, so equal sources in a form stay apart.
    class TraceEntry
      HIDDEN_USES = %w[variable].freeze

      def initialize(**fields)
        @fields = fields
      end

      # The fields of the trace file.
      def to_h
        { source: self.class::SOURCE, **@fields }
      end

      def name
        @fields[:name]
      end

      # The x-fhir-query of a query or an `_include`, else `nil`.
      def query
        @fields[:query]
      end

      # A source no item uses is left out, unless a subclass says otherwise.
      def shown?
        item_uses.any?
      end

      # The uses sections list. Uses that only define a variable are left out:
      # the items that read the variable are listed instead.
      def item_uses
        @item_uses ||= @fields[:used_in].to_a.reject { |usage| HIDDEN_USES.include?(usage[:extension]) }
      end

      # The parameters of the search it makes, or `nil` when it makes no search.
      def search_params; end

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
        SOURCE = "launch_context"

        def request_test(router, group)
          router.read_test(group)
        end

        def heading(resource)
          "**Launch context #{name}**: the #{resource} the form is opened for"
        end
      end

      # An x-fhir-query variable: a search, or a read of one resource by id.
      class Query < TraceEntry
        SOURCE = "query"

        # A query that fetches other resources through `_include` is shown even
        # when no item reads its own results.
        def shown?
          super || includes.any?
        end

        def request_test(router, group)
          read? ? router.read_test(group) : router.search_test(group, params)
        end

        def search_params
          params unless read?
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
          @fields[:read]
        end

        def includes
          @includes ||= QuerySearch.includes(query)
        end
      end

      # What a query fetches through one `_include` target. Its request is the
      # query's, so its test can be in the group of the query's own type.
      class Include < TraceEntry
        SOURCE = "include"

        def request_test(router, group)
          router.include_test(group, QuerySearch.target(query)[:resource_type], params)
        end

        def heading(resource)
          "**Query #{name}**: fetches #{resource} resources through _include=#{@fields[:include]}"
        end
      end

      # A contained resource a `templateExtract` fills from the answers. It is
      # shown even when it is extracted from the whole form, which no item uses.
      class Template < TraceEntry
        SOURCE = "template_extract"

        def shown?
          true
        end

        def request_test(router, group)
          patch? ? router.patch_test(group) : router.create_test(group)
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

      private

      # The parameters that select resources in the query.
      def params
        @params ||= QuerySearch.params(query)
      end
    end
  end
end
