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
        destination = own(group, "search", search_names: names) unless names.empty?
        destination&.with(label: "search by #{group.test_kind(destination.test_id)[:search_names].join(" + ")}")
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

      # A FHIRPath Patch goes to the patch test, then the update test.
      def patch_test(group)
        own(group, "patch") || own(group, "update")
      end

      private

      def include_in(base, names, target)
        index = Generator::TestIndex.new(base)
        targets = [target]
        id = index.find("include", search_names: names, include_targets: targets) ||
             index.find("include", include_targets: targets)
        Destination.new(base, id, "include", "search with _include in #{base.title || base.resource}") if id
      end

      # The group's test of this kind, labeled by the kind unless `label` says otherwise.
      def own(group, kind, label: kind, **details)
        id = Generator::TestIndex.new(group).find(kind, **details)
        Destination.new(group, id, kind, label) if id
      end
    end
  end
end
