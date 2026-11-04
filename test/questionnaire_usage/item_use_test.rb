# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Verifies what an item use says about itself: how sections name it and what
    # the trace file records.
    class ItemUseTest < Minitest::Test
      def test_it_comes_from_an_item_with_its_link_id_and_text
        use = ItemUse.of({ "linkId" => "dob", "text" => "Date of birth" }, "initialExpression", reads: ["birthDate"])

        assert_equal "dob", use.link_id
        assert_equal "Date of birth", use.text
        assert_equal ["birthDate"], use.reads
      end

      def test_the_narrative_of_the_questionnaire_root_is_not_its_text
        use = ItemUse.of({ "text" => { "status" => "generated" } }, "itemExtractionContext")

        assert_nil use.text
        assert_equal "The whole form", use.label
      end

      def test_the_label_is_the_text_with_its_markdown_escaped_and_spaces_collapsed
        assert_equal "Date \\*of\\* birth\\_x", ItemUse.new(text: "Date  *of*\n birth_x").label
      end

      def test_the_label_falls_back_to_the_link_id_then_the_whole_form
        assert_equal "dob", ItemUse.new(link_id: "dob", text: " ").label
        assert_equal "The whole form", ItemUse.new.label
      end

      def test_the_action_says_what_the_extension_does_to_the_item
        assert_equal "pre-fills the answer", ItemUse.new(extension: "initialExpression").action
        assert_equal "maxValue", ItemUse.new(extension: "maxValue").action
        assert_nil ItemUse.new.action
      end

      def test_a_variable_definition_is_told_apart
        assert_predicate ItemUse.new(extension: "variable"), :variable?
        refute_predicate ItemUse.new(extension: "initialExpression"), :variable?
      end

      def test_the_trace_file_fields_leave_out_what_it_does_not_have
        assert_equal({ link_id: "dob", extension: "initialExpression" },
                     ItemUse.new(link_id: "dob", extension: "initialExpression").to_h)
        assert_equal({ link_id: "dob", text: "Date", extension: "x", via: "Alias", reads: ["id"] },
                     ItemUse.new(link_id: "dob", text: "Date", extension: "x", via: "Alias", reads: ["id"]).to_h)
      end

      def test_two_uses_with_the_same_fields_are_the_same_use
        assert_equal [ItemUse.new(link_id: "dob")], [ItemUse.new(link_id: "dob"), ItemUse.new(link_id: "dob")].uniq
      end
    end
  end
end
