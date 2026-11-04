# frozen_string_literal: true

require_relative "element_reads"
require_relative "forms"
require_relative "usage_section"

module InfernoSuiteGenerator
  module QuestionnaireUsage
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

      # placements: the group's Delivery::Placements.
      def initialize(group, placements)
        @group = group
        @placements = placements.select(&:shown?)
      end

      def empty?
        @placements.empty?
      end

      def markdown
        lines = [UsageSection::HEADING, "", intro, "", forms_list]
        not_tested = UsageSection.new(entries(@placements.reject(&:request)), @group, search_check: true)
        lines.push("", "**Not tested by this group**", "", NOT_TESTED, "", not_tested.list) unless not_tested.empty?
        not_checked = ElementReads.new(entries(@placements), @group).list(checked: false)
        lines.push("", "**Elements not checked**", "", NOT_CHECKED, "", not_checked) unless not_checked.empty?
        "#{lines.join("\n")}\n"
      end

      private

      def intro
        "These questionnaires in the IG read or create #{@group.profile_name || @group.resource} resources. The " \
          "tests that make the same requests list the form items that depend on them."
      end

      def forms_list
        by_form = @placements.group_by { |placement| placement.entry.form_key }
        Forms.new(entries(@placements)).map do |title, form_entries|
          labels = test_labels(by_form[form_entries.first.form_key])
          next "- **#{title}**: no test in this group makes its requests" if labels.empty?

          "- **#{title}**: see the #{sentence(labels)} #{labels.size == 1 ? "test" : "tests"}"
        end.join("\n")
      end

      # The tests that make a request first, then the Must Support test.
      # :reek:UtilityFunction
      def test_labels(placements)
        tests = placements.filter_map(&:request) + placements.filter_map(&:must_support)
        tests.map(&:label).uniq
      end

      # :reek:UtilityFunction
      def entries(placements)
        placements.map(&:entry)
      end

      # :reek:UtilityFunction
      def sentence(labels)
        labels.size > 1 ? "#{labels[0...-1].join(", ")} and #{labels.last}" : labels.first
      end
    end
  end
end
