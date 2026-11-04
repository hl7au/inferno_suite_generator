# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Verifies the group summary: the questionnaires with the tests that list
    # them, and what no test checks.
    class GroupSummaryTest < Minitest::Test
      include UsageSectionFixtures

      READ = Router::Destination.new(nil, "patient_read", "read", "read")
      MUST_SUPPORT = Router::Destination.new(nil, "patient_must_support", "must_support", "Must Support")

      def test_names_the_tests_that_list_each_questionnaire
        markdown = summary(placement(launch_entry, request: READ, must_support: MUST_SUPPORT))

        assert_includes markdown, "- **#{FORM_TITLE}**: see the read and Must Support tests\n"
        refute_includes markdown, "**Not tested by this group**"
      end

      def test_lists_the_sources_no_test_makes_with_the_search_check
        markdown = summary(placement(query_entry("Patient?name={{%name}}")))

        assert_includes markdown, "- **#{FORM_TITLE}**: no test in this group makes its requests\n"
        assert_includes markdown, <<~MARKDOWN
          **Not tested by this group**

          #{GroupSummary::NOT_TESTED}

          - **#{FORM_TITLE}**
            - **Query Patients**: searches Patient resources
              - Request: Patient?name={{%name}}
              - A search by name; this group tests _id, family + gender
        MARKDOWN
      end

      def test_lists_the_elements_no_test_checks
        entry = launch_entry(reads: %w[birthDate contact])

        assert summary(placement(entry, request: READ)).end_with?(<<~MARKDOWN)
          **Elements not checked**

          #{GroupSummary::NOT_CHECKED}

          - **#{FORM_TITLE}**
            - **contact**: Date of birth
        MARKDOWN
      end

      def test_is_empty_when_no_entry_is_shown
        assert_predicate GroupSummary.new(patient_group, [placement(launch_entry(used_in: []))]), :empty?
      end

      private

      def placement(entry, request: nil, must_support: nil)
        Delivery::Placement.new(group: patient_group, entry:, request:, must_support:)
      end

      def summary(*placements)
        GroupSummary.new(patient_group, placements).markdown
      end
    end
  end
end
