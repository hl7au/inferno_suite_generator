# frozen_string_literal: true

require_relative "questionnaire_usage_helpers"

module InfernoSuiteGenerator
  class QuestionnaireUsageLabelsTest < Minitest::Test
    include QuestionnaireUsageHelpers

    def test_item_lines_and_must_support_labels_are_capped
      entry = patient_entry(form((1..27).map { |index| item("q#{index}", "Item #{index}", "%patient.name.family") }))
      labels = (1..10).map { |index| "Item #{index}" }.join(", ")

      assert_includes entry["patient_read"], "    - **Item 25**: pre-fills the answer; reads name.family\n    " \
                                             "- and 2 more items\n"
      refute_includes entry["patient_read"], "Item 26"
      assert_includes entry["patient_must_support"], "  - **name.family**: #{labels}, and 17 more\n"
    end

    def test_forms_without_url_are_named_by_id_and_kept_apart
      forms = [form(url: nil, title: nil, id: "first-form"), form(url: nil, title: nil, id: "second-form"),
               form(url: nil, title: nil, id: nil)]

      assert_includes patient_entry(*forms)[:group], "- **first-form**: #{BOTH_TESTS}\n" \
                                                     "- **second-form**: #{BOTH_TESTS}\n" \
                                                     "- **Untitled questionnaire**: #{BOTH_TESTS}\n"
    end

    def test_forms_with_the_same_title_show_their_versions
      forms = [form(version: "1.0.0"), form(version: "2.0.0"), form(url: "http://example.org/other"),
               form(version: "1.0.0")]

      assert_includes patient_entry(*forms)[:group], "- **Demo form, version 1.0.0**: #{BOTH_TESTS}\n" \
                                                     "- **Demo form, version 2.0.0**: #{BOTH_TESTS}\n" \
                                                     "- **Demo form**: #{BOTH_TESTS}\n\n"
    end

    def test_item_labels_are_escaped_and_uses_merged_per_item
      items = [item("odd", "  Patient's *first*\n name_[x] `code` ", "%patient.name.family"),
               item("dup", nil, "%patient.name.family", expression("%patient.name.family", "enableWhenExpression"),
                    "%patient.name.family", "%patient.exists()")]
      root = [launch("patient", "Patient"), expression("%patient.name.given", "itemPopulationContext")]

      escaped = %q(Patient's \*first\* name\_\[x\] \`code\`)

      assert_equal ["    - **The whole form**: sets the population context; reads name.given (not checked)\n",
                    "    - **#{escaped}**: pre-fills the answer; reads name.family\n",
                    "    - **dup**: pre-fills the answer, shows or hides the item; reads name.family\n"],
                   patient_entry(form(items, extension: root))["patient_read"].lines.grep(/^    - /)
    end

    def test_old_sdc_launch_context_name_and_item_without_paths
      read = patient_entry(form([item("seen", "Seen", "%patient.exists()")],
                                contexts: [launch("patient", "Patient", key: "valueId")]))["patient_read"]

      assert_includes read, "  - **Launch context patient**: the Patient the form is opened for\n    " \
                            "- **Seen**: pre-fills the answer\n"
    end

    def test_groups_without_recorded_tests_raise
      error = assert_raises(RuntimeError) { describe(ig(form), group(tests: [])) }

      assert_equal "Questionnaire usage tracing must run after the test generators: no group has a recorded test.",
                   error.message
      assert_empty describe(ig(form))
    end

    def test_malformed_shapes_are_treated_as_absent
      patient = group
      nameless = { "url" => "#{SDC}launchContext", "extension" => [{ "url" => "type", "valueCode" => "Patient" }] }
      malformed = [form(url: "a", item: { "linkId" => "x" }, extension: { "url" => "x" }, contained: "x"),
                   form([{ "linkId" => "x", "extension" => { "url" => "y" }, "item" => "z" }],
                        url: "b", contexts: [nameless]),
                   form([item("bad", "Bad", "%patient.name.(", ""), *default_items], text: 5, contained: "x")]

      assert_equal section(READ_INTRO, PATIENT_SOURCE), describe(stub_ig(*malformed), patient)[patient]["patient_read"]
      assert_equal "Questionnaire usage tracing: skipping FHIRPath \"%patient.name.(\": " \
                   "Failed to parse \"%patient.name.(\"\n", @log
    end
  end
end
