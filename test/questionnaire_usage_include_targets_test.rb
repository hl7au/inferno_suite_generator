# frozen_string_literal: true

require_relative "questionnaire_usage_include_helpers"

module InfernoSuiteGenerator
  # _include sources: which chains they own, their target types, which include test lists them, and logs.
  class QuestionnaireUsageIncludeTargetsTest < Minitest::Test
    include QuestionnaireUsageIncludeHelpers

    REQUESTER = "MedicationRequest:requester"

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

      assert_includes meds_entry(mr_group, meds_query(text), med_and_substance_items)["mr_include"],
                      "#{include_heading(text, "#{INCLUDE}:Medication")}#{MED_ITEMS}"
      assert_empty @log
    end

    def test_search_parameter_target_is_used
      param = FHIR::SearchParameter.new("resourceType" => "SearchParameter", "code" => "medication",
                                        "base" => ["MedicationRequest"], "target" => ["Medication"])

      assert_includes meds_entry(mr_group, meds_query, med_and_substance_items, extra: [param])["mr_include"],
                      "#{include_heading}#{MED_ITEMS}"
      assert_empty @log
    end

    def test_include_no_item_reads_is_not_shown_but_its_query_is
      text = "MedicationRequest?patient=x&_include=#{INCLUDE}:Medication"
      mr = mr_group
      med = med_group
      result = meds_result([mr, med], meds_query(text), [])

      refute result.key?(med)
      refute result.fetch(mr).key?("mr_include")
      assert_equal query_lines(text, "    - A search by patient\n", no_reads("#{INCLUDE}:Medication")),
                   not_tested(result.fetch(mr))
    end

    def test_query_is_named_by_all_its_own_includes_resolved_or_not
      text = "MedicationRequest?_include=#{INCLUDE}:Medication&_include=MedicationRequest:requester" \
             "&_include:iterate=#{INCLUDE}"
      entry = meds_entry(mr_group, meds_query(text), [])

      assert_equal query_lines(text, no_reads("#{INCLUDE}:Medication", "MedicationRequest:requester")),
                   not_tested(entry)
    end

    def test_include_without_a_parameter_part_is_unresolved
      text = "MedicationRequest?patient=x&_include=MedicationRequest"
      result = meds_result([mr_group, med_group], meds_query(text))

      assert_equal logged("unresolved Meds form query Meds include MedicationRequest: no target type"), @log.lines
      assert_empty result
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
      other = "MedicationRequest?_include=#{REQUESTER}"
      entry = meds_entry(mr_group, [*meds_query(text), query("Other", other)])

      skipped = ["_include:iterate=#{INCLUDE}", "_include=Patient:general-practitioner"].map do |param|
        "skipping #{param} in Meds form query Meds: only _include of MedicationRequest is traced"
      end
      assert_equal logged(*skipped, "unresolved Meds form query Other include #{REQUESTER}: no target type"), @log.lines
      assert_includes entry["mr_include"], "#{include_heading(text)}#{MED_ITEMS}"
      assert_includes entry[:group], "  - **Query Other**: searches MedicationRequest resources\n    - Request: " \
                                     "#{other}\n#{no_reads(REQUESTER)}"
    end
  end
end
