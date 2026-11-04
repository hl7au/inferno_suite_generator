# frozen_string_literal: true

require_relative "element_reads"
require_relative "router"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Decides which tests list each trace entry, once and before anything is
    # rendered, so the test sections, the group summaries and the trace files
    # can't disagree.
    class Delivery
      # One trace entry of one group. `request` is the Router::Destination of
      # the test that makes its request, and `must_support` the group's Must
      # Support test when its items read an element the group checks. Each is
      # `nil` when no test lists the entry for that reason.
      Placement = Data.define(:group, :entry, :request, :must_support) do
        def shown?
          entry.shown?
        end

        # The tests whose descriptions list the entry.
        def tests
          [request, must_support].compact
        end
      end

      # A test that makes the request of these entries, and the groups they
      # were traced for. Only an `_include` test has several groups: its entries
      # link to every group of the target type.
      TestListing = Data.define(:destination, :entries, :groups)

      # traces: `{ profile_url => [trace entries] }`, from `Tracer#trace`.
      def initialize(groups, traces)
        router = Router.new(groups)
        @placements = groups.filter_map do |group|
          entries = traces[group.profile_url]
          [group, placements(group, entries, router)] if entries
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
        TestListing.new(destination: placements.first.request, entries: placements.map(&:entry).uniq,
                        groups: placements.map(&:group).uniq)
      end

      def placements(group, entries, router)
        reads = ElementReads.new(entries, group)
        must_support = router.must_support_test(group)
        entries.map do |entry|
          request = router.source_test(group, entry) if entry.shown?
          Placement.new(group:, entry:, request:, must_support: (must_support if reads.checks?(entry)))
        end
      end
    end
  end
end
