# frozen_string_literal: true

require_relative "questionnaire_usage_include_helpers"

module InfernoSuiteGenerator
  # A read by id takes no _include: its includes are logged, not traced, and its chains stay with the read query.
  # _include:iterate and an _include of another type log the §4 message instead.
  class QuestionnaireUsageIncludeReadTest < Minitest::Test
    include QuestionnaireUsageIncludeHelpers

    READ = "MedicationRequest/1?_include=#{INCLUDE}".freeze

    def skipped(param, reason = "a read by id takes no _include") = "skipping #{param} in Meds form query Meds: #{reason}"

    def test_read_query_include_is_not_traced
      mr = mr_group
      result = meds_result([mr, med_group], meds_query(READ))

      assert_equal logged(skipped("_include=#{INCLUDE}")), @log.lines
      refute_includes result.values.flat_map(&:values).join, "through _include"
      refute result.fetch(mr, {}).key?("mr_include")
    end

    def test_read_query_keeps_the_chains_that_pick_the_include_target
      assert_includes not_tested(meds_entry(mr_group, meds_query(READ))),
                      "  - **Query Meds**: reads one MedicationRequest by id\n    - Request: #{READ}\n    " \
                      "- **Medication**: pre-fills the answer; reads entry.resource.code (not checked), entry.resource"
    end

    def test_read_query_with_only_includes_is_not_shown
      foreign = ["_include:iterate=#{INCLUDE}", "_include=Patient:general-practitioner"]
      params = ["_include=#{INCLUDE}", *foreign]

      assert_empty meds_result([mr_group, med_group], meds_query("MedicationRequest/1?#{params.join("&")}"), [])
      assert_equal logged(skipped(params.first),
                          *foreign.map { |param| skipped(param, "only _include of MedicationRequest is traced") }),
                   @log.lines
    end
  end
end
