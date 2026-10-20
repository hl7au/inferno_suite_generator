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
        QuestionnaireAwareGroupGenerator.traces = { BODY_HEIGHT => [query_entry] }

        assert_equal "#{plain_description}\n#{expected_section}", description
      end

      def test_a_group_without_a_trace_gets_todays_description
        QuestionnaireAwareGroupGenerator.traces = { "http://example.org/other" => [query_entry] }

        assert_equal plain_description, description
      end

      def test_added_text_is_escaped_for_the_group_template_literal
        entry = query_entry(used_in: [{ link_id: "height", text: TRICKY_TEXT }])
        QuestionnaireAwareGroupGenerator.traces = { BODY_HEIGHT => [entry] }

        assert_includes description, "**Height \\(cm\\) \\\#{x} \\\#@y \\\\ z"
        assert_includes eval("%(#{description})", binding, __FILE__, __LINE__), TRICKY_TEXT # rubocop:disable Security/Eval
      end

      private

      def expected_section
        <<~MARKDOWN
          ## Used in questionnaires

          These questionnaires in the IG read or create AU Core Body Height resources. A form can pre-fill an item only if the server returns the elements the item reads. Elements marked \\(not checked\\) are neither Must Support nor required by the profile, so this group's tests do not check them.

          - **#{FORM_TITLE}**
            - **Query ObsBodyHeight**: searches Observation resources
              - Request: #{HEIGHT_QUERY}
              - This group tests the same search: patient + code
              - **Height**: pre-fills the answer, shows or hides the item; reads value.value, effective \\(not checked\\)
        MARKDOWN
      end

      def query_entry(used_in: [{ link_id: "height", text: "Height", extension: "initialExpression",
                                  reads: %w[value.value effective] },
                                { link_id: "height", text: "Height", extension: "enableWhenExpression",
                                  reads: ["value.value"] }])
        { source: "query", questionnaire_title: FORM_TITLE, name: "ObsBodyHeight",
          query: HEIGHT_QUERY, elements_read: %w[value.value effective], used_in: }
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
                                     searches: [{ names: %w[patient code] }],
                                     must_supports: { elements: [{ path: "value[x]:valueQuantity.value" }] })
      end
    end
  end
end
