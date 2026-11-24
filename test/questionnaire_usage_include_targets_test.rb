# frozen_string_literal: true

require_relative "questionnaire_usage_include_helpers"

module InfernoSuiteGenerator
  # _include sources: which chains they own, their target types, which include test lists them, and logs.
  class QuestionnaireUsageIncludeTargetsTest < Minitest::Test
    include QuestionnaireUsageIncludeHelpers

    def test_entry_filters_and_picked_entry_variables_belong_to_the_include
      root = [*meds_query, variable("Picked", "%Meds.entry.where(resource is Medication)")]
      items = [item("med", "Medication", "%Picked.resource.code"),
               item("status", "Status", "%Meds.entry.resource.status"),
               item("dose", "Dose form", "%Meds.entry.resource.ofType(Medication).form")]
      entry = meds_entry(mr_group, root, items)

      assert_equal query_lines(MEDS_QUERY, "    - A search by patient\n",
                               "    - **Status**: pre-fills the answer; reads status (not checked)\n"),
                   not_tested(entry)
      assert_includes entry["mr_include"], "#{include_heading}#{MED_ITEMS}"
    end

    def test_explicit_target_is_used
      text = "MedicationRequest?patient=x&_include=#{INCLUDE}:Medication"

      assert_includes meds_entry(mr_group, meds_query(text), [])["mr_include"],
                      include_heading(text, "#{INCLUDE}:Medication")
    end

    def test_search_parameter_target_is_used
      param = FHIR::SearchParameter.new("resourceType" => "SearchParameter", "code" => "medication",
                                        "base" => ["MedicationRequest"], "target" => ["Medication"])

      assert_includes meds_entry(mr_group, meds_query, [], extra: [param])["mr_include"], include_heading
    end

    def test_target_is_inferred_from_the_type_the_form_picks
      items = [item("code", "Code", "%Meds.entry.resource.where(resourceType = 'Medication').code")]

      assert_includes meds_entry(mr_group, meds_query, items)["mr_include"],
                      "#{include_heading}    - **Code**: pre-fills the answer; reads code\n"
    end

    def test_exact_parameters_include_test_is_preferred
      mr = mr_group(includes: [["mr_include_status", %w[status], %w[Medication]],
                               ["mr_include_patient", %w[patient], %w[Medication]]])
      entry = meds_entry(mr)

      assert entry.key?("mr_include_patient")
      refute entry.key?("mr_include_status")
    end

    def test_include_without_an_include_test_is_not_tested_in_the_target_group
      med = med_group
      summary = meds_result([mr_group(includes: []), med]).fetch(med)[:group]

      assert_includes summary, "#{NOT_TESTED}\n\n- **Meds form**\n#{include_heading}#{MED_ITEMS}"
      refute_includes summary, LABEL
    end

    def test_untraced_includes_log_and_leave_the_rest_intact
      text = "#{MEDS_QUERY}&_include:iterate=#{INCLUDE}&_include=Patient:general-practitioner"
      other = query("Other", "MedicationRequest?_include=MedicationRequest:requester")
      entry = meds_entry(mr_group, [*meds_query(text), other])

      skipped = "in Meds form query Meds: only _include of MedicationRequest is traced"
      assert_equal logged("skipping _include:iterate=#{INCLUDE} #{skipped}",
                          "skipping _include=Patient:general-practitioner #{skipped}",
                          "unresolved Meds form query Other include MedicationRequest:requester: no target type"),
                   @log.lines
      assert_includes entry["mr_include"], "#{include_heading(text)}#{MED_ITEMS}"
      refute_includes entry[:group], "Query Other"
    end
  end
end
