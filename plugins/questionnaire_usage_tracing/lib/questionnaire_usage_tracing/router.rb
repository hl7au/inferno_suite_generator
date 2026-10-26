# frozen_string_literal: true

require_relative "query_search"

module InfernoSuitePlugins
  module QuestionnaireUsageTracing
    # Finds the test that makes a trace entry's request, through the host's
    # `TestIndex`:
    #
    # - a launch context, or a query that reads one resource by id: the read test
    # - a search query: the search test by the same parameters, in any order
    # - an `_include`: the include test for the entry's type in the group of
    #   the query's own type, preferably the one that searches by the query's
    #   parameters
    # - a template: the create test, or for a FHIRPath Patch the patch test,
    #   then the update test
    #
    # The test can be in another group than the entry, for an `_include`.
    class Router
      # Where an entry's text goes. `label` names the test in the group summary.
      Destination = Data.define(:group, :test_id, :kind, :label)

      def initialize(context)
        @context = context
        @groups = context.groups
      end

      # The Destination for the entry of `group`, or `nil` when no test makes
      # its request.
      def source_test(group, entry)
        case entry[:source]
        when "launch_context" then own(group, "read")
        when "query" then query_test(group, entry)
        when "include" then include_test(group, entry)
        when "template_extract" then template_test(group, entry)
        end
      end

      def must_support_test(group)
        own(group, "must_support", label: "Must Support")
      end

      private

      def query_test(group, entry)
        query = entry[:query]
        return own(group, "read") if entry[:read]

        names = QuerySearch.params(query)
        destination = own(group, "search", search_names: names) unless names.empty?
        destination&.with(label: "search by #{group.test_kind(destination.test_id)[:search_names].join(" + ")}")
      end

      def include_test(group, entry)
        query = entry[:query]
        type = QuerySearch.target(query)[:resource_type]
        names = QuerySearch.params(query)
        @groups.lazy.select { |base| base.resource == type }
               .filter_map { |base| include_in(base, names, group.resource) }.first
      end

      def include_in(base, names, target)
        index = @context.test_index(base)
        targets = [target]
        id = index.find("include", search_names: names, include_targets: targets) ||
             index.find("include", include_targets: targets)
        Destination.new(base, id, "include", "search with _include in #{base.title || base.resource}") if id
      end

      def template_test(group, entry)
        return own(group, "create") unless entry[:patch]

        own(group, "patch") || own(group, "update")
      end

      # The group's test of this kind, labeled by the kind unless `label` says otherwise.
      def own(group, kind, label: kind, **details)
        id = @context.test_index(group).find(kind, **details)
        Destination.new(group, id, kind, label) if id
      end
    end
  end
end
