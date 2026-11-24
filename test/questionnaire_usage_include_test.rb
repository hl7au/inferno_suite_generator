# frozen_string_literal: true

require_relative "questionnaire_usage_include_helpers"

module InfernoSuiteGenerator
  # _include sources: listed by the searching group's include test and named in both groups' summaries.
  class QuestionnaireUsageIncludeTest < Minitest::Test
    include QuestionnaireUsageIncludeHelpers

    def test_include_is_listed_once_by_the_include_test_of_the_searching_group
      mr = mr_group
      result = meds_result([mr, med_group, med_group("http://example.org/StructureDefinition/med2")])

      assert_equal section(INCLUDE_INTRO, "- **Meds form**\n#{include_heading}#{MED_ITEMS.chomp}"),
                   result[mr]["mr_include"]
    end

    def test_same_include_written_twice_is_one_source
      mr = mr_group
      result = meds_result([mr, med_group], meds_query("#{MEDS_QUERY}&_include=#{INCLUDE}"))

      assert_equal section(INCLUDE_INTRO, "- **Meds form**\n#{include_heading("#{MEDS_QUERY}&_include=#{INCLUDE}")}" \
                                          "#{MED_ITEMS.chomp}"),
                   result[mr]["mr_include"]
    end

    def test_both_summaries_name_the_searching_group_and_it_shows_the_no_reads_line
      mr = mr_group
      med = med_group
      mr_summary, med_summary = meds_result([mr, med]).values_at(mr, med).map { |entry| entry[:group] }

      assert_includes mr_summary, LINE
      assert_includes mr_summary, query_lines(MEDS_QUERY, "    - A search by patient\n", NO_READS)
      assert_includes med_summary, "- **Meds form**: see the #{LABEL} and Must Support tests\n"
      refute_includes med_summary, "Medication Tests"
    end

    def test_include_label_uses_the_title_else_the_resource
      assert_includes meds_entry(mr_group(title: "Prescriptions"))[:group], "search with _include in Prescriptions"
      assert_includes meds_entry(mr_group(title: ""))[:group], LINE
    end

    def test_searching_group_no_source_fits_when_its_only_profile_conflicts
      text = "MedicationRequest?category=#{MR_CATEGORY}|inpatient&patient={{%patient.id}}&_include=#{INCLUDE}"
      entry = meds_entry(mr_group, meds_query(text), extra: [mr_profile(MR_URL, "community")])

      assert_includes @log, "unresolved Meds form query Meds: the MedicationRequest profile fixes"
      assert_includes entry["mr_include"], include_heading(text)
      assert_includes entry[:group], LINE
      refute_includes entry[:group], NOT_TESTED
    end

    def test_searching_group_no_source_fits_when_no_profile_matches_the_codes
      text = "MedicationRequest?category=#{MR_CATEGORY}|inpatient&_include=#{INCLUDE}"
      first = mr_group(url: "#{MR_URL}1")
      second = mr_group(url: "#{MR_URL}2", includes: [])
      result = meds_result([first, second, med_group], meds_query(text), extra: two_mr_profiles)
      entry = result.fetch(first)

      assert_includes @log, "unresolved Meds form query Meds: no MedicationRequest profile matches"
      assert_includes entry["mr_include"], include_heading(text)
      assert_includes entry[:group], LINE
      refute result.key?(second)
    end

    def test_query_without_parameters_fits_the_searching_group_and_is_not_tested_there
      text = "MedicationRequest?_include=#{INCLUDE}"
      entry = meds_entry(mr_group, meds_query(text))

      assert_includes entry["mr_include"], include_heading(text)
      assert_equal query_lines(text, NO_READS), not_tested(entry)
    end
  end
end
