# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # Verifies `QuestionnaireAwareGroupGenerator` adds the "Used in
    # questionnaires" section to the descriptions of traced groups only.
    class QuestionnaireAwareGroupGeneratorTest < Minitest::Test
      include TracerFixtures
      include ConfigKeeperSwap

      TRICKY_TEXT = "Height (cm) \#{x} \#@y \\ z"

      def test_a_group_with_a_trace_gets_the_section
        QuestionnaireAwareGroupGenerator.traces = { BODY_HEIGHT => [query_entry, launch_context_entry] }

        assert_equal "#{plain_description}\n#{expected_section}", description
      end

      def test_a_group_without_a_trace_gets_todays_description
        QuestionnaireAwareGroupGenerator.traces = { "http://example.org/other" => [query_entry] }

        assert_equal plain_description, description
      end

      def test_added_text_is_escaped_for_the_group_template_literal
        entry = query_entry(used_in: [{ link_id: "height", text: TRICKY_TEXT }])
        QuestionnaireAwareGroupGenerator.traces = { BODY_HEIGHT => [entry] }

        assert_includes description, "`height` Height \\(cm\\) \\\#{x} \\\#@y \\\\ z"
        assert_includes eval("%(#{description})", binding, __FILE__, __LINE__), TRICKY_TEXT # rubocop:disable Security/Eval
      end

      def test_more_than_ten_items_show_as_a_count
        used_in = (1..11).map { |index| { link_id: "item-#{index}", text: "Item #{index}" } }
        QuestionnaireAwareGroupGenerator.traces = { BODY_HEIGHT => [query_entry(used_in:)] }

        assert_includes description, "  * Items: 11 items\n"
      end

      private

      def expected_section
        <<~MARKDOWN
          ## Used in questionnaires

          ### #{FORM_TITLE}

          * Query `ObsBodyHeight`: `Observation?code=8302-2&_sort=-date&patient={{%patient.id}}`
            * Reads: `value.value`, `effective`
            * Items: `height` Height
          * Launch context `patient`
            * Reads: `birthDate`
            * Items: `dob` Date of birth
        MARKDOWN
      end

      def query_entry(used_in: [{ link_id: "height", text: "Height", extension: "initialExpression" },
                                { link_id: "height", text: "Height", extension: "enableWhenExpression" }])
        { source: "query", questionnaire_title: FORM_TITLE, name: "ObsBodyHeight",
          query: HEIGHT_QUERY, elements_read: %w[value.value effective], used_in: }
      end

      def launch_context_entry
        { source: "launch_context", questionnaire_title: FORM_TITLE, name: "patient",
          elements_read: ["birthDate"], used_in: [{ link_id: "dob", text: "Date of birth" }] }
      end

      def description
        QuestionnaireAwareGroupGenerator.new(group, @result_folder, nil).description
      end

      def plain_description
        Generator::GroupGenerator.new(group, @result_folder, nil).description
      end

      def group
        Generator::GroupMetadata.new(resource: "Observation", profile_url: BODY_HEIGHT,
                                     profile_name: "AU Core Body Height", title: "Body Height", version: "2.0.0",
                                     searches: [])
      end
    end
  end
end
