# frozen_string_literal: true

require_relative "../core/test_index"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Finds the test that makes a request, through `Generator::TestIndex`. Each
    # `TraceEntry` picks the lookup its request needs. Every lookup returns a
    # Destination, or `nil` when no test makes the request.
    class Router
      # Where an entry's text goes. `label` names the test in the group summary.
      Destination = Data.define(:group, :test_id, :kind, :label)

      def initialize(groups)
        @groups = groups
      end

      # The Destination for the entry of `group`.
      def source_test(group, entry)
        entry.request_test(self, group)
      end

      def must_support_test(group)
        own(group, "must_support", label: "Must Support")
      end

      def read_test(group)
        own(group, "read")
      end

      # The search test by the same parameters, in any order.
      def search_test(group, names)
        test = index(group).find("search", search_names: names) unless names.empty?
        destination(group, test, "search by #{test.details[:search_names].join(" + ")}") if test
      end

      # The include test for the group's type in a group of `searched_type`,
      # preferably the one that searches by the same parameters. It can be in
      # another group than `group`.
      def include_test(group, searched_type, names)
        @groups.lazy.select { |base| base.resource == searched_type }
               .filter_map { |base| include_in(base, names, group.resource) }.first
      end

      def create_test(group)
        own(group, "create")
      end

      # A FHIRPath Patch goes to the patch test, then the update test, not the one
      # that creates a new resource through update.
      def patch_test(group)
        own(group, "patch") || own(group, "update", option: "update")
      end

      private

      def include_in(base, names, target)
        index = index(base)
        targets = [target]
        test = index.find("include", search_names: names, include_targets: targets) ||
               index.find("include", include_targets: targets)
        destination(base, test, "search with _include in #{base.title || base.resource}") if test
      end

      # The group's test of this kind, labeled by the kind unless `label` says otherwise.
      def own(group, kind, label: kind, **details)
        test = index(group).find(kind, **details)
        destination(group, test, label) if test
      end

      # :reek:UtilityFunction
      def index(group)
        Generator::TestIndex.new(group)
      end

      # :reek:UtilityFunction
      def destination(group, test, label)
        Destination.new(group, test.id, test.kind, label)
      end
    end
  end
end
