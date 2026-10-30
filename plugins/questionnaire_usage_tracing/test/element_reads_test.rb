# frozen_string_literal: true

require_relative "support"

module InfernoSuitePlugins
  module QuestionnaireUsageTracing
    # Verifies the element lists of the Must Support test and the group
    # summary.
    class ElementReadsTest < Minitest::Test
      include UsageSectionFixtures

      def test_lists_each_checked_element_with_the_items_that_read_it
        entry = launch_entry(used_in: [usage("dob", "Date of birth", "birthDate"), usage("age", "Age", "birthDate"),
                                       usage("dob", "Date of birth", "birthDate", extension: "calculatedExpression"),
                                       usage("contact", "Contact", "contact")])

        assert_equal <<~MARKDOWN.chomp, list([entry], checked: true)
          - **#{FORM_TITLE}**
            - **birthDate**: Date of birth, Age
        MARKDOWN
        assert_equal "- **#{FORM_TITLE}**\n  - **contact**: Contact", list([entry], checked: false)
      end

      def test_extensions_are_named_as_in_the_item_lines
        entry = launch_entry(used_in: [usage("ind", "Status", "extension[url=#{INDIGENOUS_STATUS}].value"),
                                       usage("pro", "Pronouns", "extension[url=#{PRONOUNS}].value")])

        assert_includes list([entry], checked: true), "- **extension:indigenousStatus.value**: Status"
        assert_includes list([entry], checked: false), "- **extension[individual-pronouns].value**: Pronouns"
      end

      def test_uses_that_only_define_a_variable_are_left_out
        entry = launch_entry(used_in: [variable_usage])

        assert_empty list([entry], checked: false)
      end

      def test_items_beyond_the_limit_are_counted
        used_in = (1..12).map { |index| usage("item-#{index}", "Item #{index}", "birthDate") }

        assert list([launch_entry(used_in:)], checked: true).end_with?("Item 10, and 2 more")
      end

      def test_the_must_support_section_has_a_heading_or_is_empty
        section = MustSupportSection.new([launch_entry], patient_group)

        assert section.markdown.start_with?("## Used in questionnaires\n\nItems in these questionnaires read")
        assert_predicate MustSupportSection.new([launch_entry(reads: ["contact"])], patient_group), :empty?
      end

      private

      def list(entries, checked:)
        ElementReads.new(entries, patient_group).list(checked:)
      end

      def usage(link_id, text, *reads, extension: "initialExpression")
        { link_id:, text:, extension:, reads: }
      end
    end
  end
end
