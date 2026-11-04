# frozen_string_literal: true

require_relative "checked_elements"
require_relative "router"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Decides which tests list each trace entry and which elements its items
    # read count as checked, once and before anything is rendered, so the test
    # sections, the group summaries and the trace files can't disagree.
    class Delivery
      # One element path a trace entry's items read: how sections name it, and
      # whether it counts as checked.
      ElementRead = Data.define(:path, :label, :checked)

      # One trace entry of one group. `request` is the Router::Destination of
      # the test that makes its request, and `must_support` the group's Must
      # Support test when its items read an element the group checks. Each is
      # `nil` when no test lists the entry for that reason.
      #
      # `reads` and `must_support_reads` are `{ path => ElementRead }`. `reads`
      # has every path the entry's items read, and is the same for each group
      # the entry was traced for: an element is checked when any of them checks
      # it. `must_support_reads` has the paths this group checks, as it names
      # them, since its Must Support test can list only those.
      Placement = Data.define(:group, :entry, :request, :must_support, :reads, :must_support_reads) do
        def shown?
          entry.shown?
        end

        # The tests whose descriptions list the entry.
        def tests
          [request, must_support].compact
        end
      end

      # A test that makes the request of these placements, one per entry, and
      # the groups they were traced for. Only an `_include` test has several
      # groups: its entries link to every group of the target type.
      TestListing = Data.define(:destination, :placements, :groups)

      # traces: `{ profile_url => [trace entries] }`, from `Tracer#trace`.
      def initialize(groups, traces)
        router = Router.new(groups)
        reads = shared_reads(groups, traces)
        @placements = groups.filter_map do |group|
          entries = traces[group.profile_url]
          [group, placements(group, entries, router, reads)] if entries
        end
      end

      # Yields each traced group and its Placements, in trace order.
      def each_group(&)
        @placements.each(&)
      end

      # A TestListing per test that makes a request, listing a shared entry once.
      def test_listings
        requested = @placements.flat_map(&:last).select(&:request)
        requested.group_by { |placement| placement.request.test_id }.values.map { |listed| listing(listed) }
      end

      private

      # :reek:UtilityFunction
      def listing(placements)
        TestListing.new(destination: placements.first.request, placements: placements.uniq(&:entry),
                        groups: placements.map(&:group).uniq)
      end

      def placements(group, entries, router, reads)
        checked_elements = CheckedElements.new([group])
        must_support = router.must_support_test(group)
        entries.map do |entry|
          own = element_reads(entry, checked_elements).select { |_path, read| read.checked }
          request = router.source_test(group, entry) if entry.shown?
          Placement.new(group:, entry:, request:, must_support: (must_support if own.any?), reads: reads[entry],
                        must_support_reads: own)
        end
      end

      # `{ entry => { path => ElementRead } }`, answered for all the groups each
      # entry was traced for.
      def shared_reads(groups, traces)
        groups_by_entry = groups.each_with_object({}) do |group, found|
          traces[group.profile_url].to_a.each { |entry| (found[entry] ||= []) << group }
        end
        groups_by_entry.to_h { |entry, traced| [entry, element_reads(entry, CheckedElements.new(traced))] }
      end

      # :reek:UtilityFunction
      def element_reads(entry, checked_elements)
        paths = entry.item_uses.flat_map(&:reads).uniq
        paths.to_h do |path|
          [path, ElementRead.new(path:, label: checked_elements.label(path), checked: checked_elements.checked?(path))]
        end
      end
    end
  end
end
