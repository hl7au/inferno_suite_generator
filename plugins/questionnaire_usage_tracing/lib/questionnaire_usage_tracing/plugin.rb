# frozen_string_literal: true

module InfernoSuitePlugins
  module QuestionnaireUsageTracing
    # Traces every Questionnaire in the IG over the suite's groups and splits
    # each group's trace over its tests:
    #
    # - each entry goes to the test that makes its request (Router), as a
    #   "Used in questionnaires" section in that test's description
    # - the elements items read go to the Must Support test, by element
    # - the group description gets a GroupSummary: the questionnaires, the
    #   tests that list them, and what no test checks
    #
    # Each traced group gets its entries under "questionnaire_usage_tracing" in
    # <group dir>/plugins.yml, each with the ids of the tests that list it as
    # `tested_by`.
    class Plugin < InfernoSuiteGenerator::Plugins::Base
      def generate(context)
        traces = Tracer.new(context.ig_resources, context.groups).trace
        router = Router.new(context)
        tests = TestSections.new(context)
        context.groups.each do |group|
          entries = traces[group.profile_url]
          GroupTrace.new(group, entries, router, tests).write(context) if entries
        end
        tests.write
      end
    end

    # One group's trace entries and the tests they go to.
    class GroupTrace
      def initialize(group, entries, router, tests)
        @group = group
        @entries = entries
        @must_support = router.must_support_test(group)
        @destinations = entries.select { |entry| UsageSection.shown?(entry) }
                               .each_with_object({}.compare_by_identity) do |entry, destinations|
          destinations[entry] = router.source_test(group, entry)
        end
        @destinations.each { |entry, destination| tests.add(destination, entry, group) if destination }
      end

      def write(context)
        write_must_support(context.descriptions)
        context.metadata.group(@group, entries: @entries.map { |entry| entry.merge(tested_by: tested_by(entry)) })
        summary = GroupSummary.new(@group, @entries, @destinations, @must_support)
        context.descriptions.group(@group, summary.markdown) unless summary.empty?
      end

      private

      def write_must_support(descriptions)
        section = MustSupportSection.new(@entries, @group)
        descriptions.test(@group, @must_support.test_id, section.markdown) if @must_support && !section.empty?
      end

      # The ids of the tests whose descriptions list the entry: the one that
      # makes its request, and the Must Support test when its items read an
      # element that test checks.
      def tested_by(entry)
        checks = @must_support && !ElementReads.new([entry], @group).list(checked: true).empty?
        [@destinations[entry]&.test_id, (@must_support.test_id if checks)].compact
      end
    end
  end
end
