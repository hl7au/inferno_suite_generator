# frozen_string_literal: true

require_relative "element_reads"
require_relative "forms"
require_relative "usage_section"

module InfernoSuitePlugins
  module QuestionnaireUsageTracing
    # The "Used in questionnaires" Markdown at the end of a group description.
    # The details are in the descriptions of the tests that make each request,
    # so the group lists what is left:
    #
    # - each questionnaire, with the tests that list its items
    # - **Not tested by this group**: the sources no test makes the request of
    # - **Elements not checked**: the elements items read that no test checks
    class GroupSummary
      NOT_TESTED = "No test in this group makes these requests or writes these resources, so nothing checks what " \
                   "these forms get from them."
      NOT_CHECKED = "The profile neither marks these elements Must Support nor requires them, so no test checks " \
                    "that the server returns them."

      # destinations: `{ entry => Router::Destination or nil }`, compared by identity.
      # must_support_test: the group's Must Support Router::Destination, or `nil`.
      def initialize(group, entries, destinations, must_support_test)
        @group = group
        @entries = entries.select { |entry| UsageSection.shown?(entry) }
        @destinations = destinations
        @must_support_test = must_support_test
      end

      def empty?
        @entries.empty?
      end

      def markdown
        lines = [UsageSection::HEADING, "", intro, "", forms_list]
        not_tested = UsageSection.new(@entries.reject { |entry| @destinations[entry] }, @group, search_check: true)
        lines.push("", "**Not tested by this group**", "", NOT_TESTED, "", not_tested.list) unless not_tested.empty?
        not_checked = ElementReads.new(@entries, @group).list(checked: false)
        lines.push("", "**Elements not checked**", "", NOT_CHECKED, "", not_checked) unless not_checked.empty?
        "#{lines.join("\n")}\n"
      end

      private

      def intro
        "These questionnaires in the IG read or create #{@group.profile_name || @group.resource} resources. The " \
          "tests that make the same requests list the form items that depend on them."
      end

      def forms_list
        Forms.new(@entries).map do |title, entries|
          labels = test_labels(entries)
          next "- **#{title}**: no test in this group makes its requests" if labels.empty?

          "- **#{title}**: see the #{sentence(labels)} #{labels.size == 1 ? "test" : "tests"}"
        end.join("\n")
      end

      def test_labels(entries)
        labels = entries.filter_map { |entry| @destinations[entry]&.label }.uniq
        checks_elements = !ElementReads.new(entries, @group).list(checked: true).empty?
        @must_support_test && checks_elements ? [*labels, @must_support_test.label] : labels
      end

      # :reek:UtilityFunction
      def sentence(labels)
        labels.size > 1 ? "#{labels[0...-1].join(", ")} and #{labels.last}" : labels.first
      end
    end
  end
end
