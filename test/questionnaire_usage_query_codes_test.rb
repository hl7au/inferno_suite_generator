# frozen_string_literal: true

require_relative "questionnaire_usage_query_helpers"

module InfernoSuiteGenerator
  # Which query parameters give codes, the codes a profile fixes, and the single-profile conflict rule.
  class QuestionnaireUsageQueryCodesTest < Minitest::Test
    include QuestionnaireUsageQueryHelpers

    CATEGORY = "http://terminology.hl7.org/CodeSystem/observation-category"
    VITALS_URL = "http://example.org/StructureDefinition/vitals"

    # Fixes code 8302-2 by patternCoding on Observation.code.coding, and category vital-signs by a coding slice.
    def vitals_profile
      elements = [{ "id" => "Observation.code.coding", "path" => "Observation.code.coding",
                    "patternCoding" => { "system" => LOINC, "code" => "8302-2" } },
                  { "id" => "Observation.category:vs.coding.system", "path" => "Observation.category.coding.system",
                    "patternUri" => CATEGORY },
                  { "id" => "Observation.category:vs.coding.code", "path" => "Observation.category.coding.code",
                    "patternCode" => "vital-signs" }]
      FHIR::StructureDefinition.new("resourceType" => "StructureDefinition", "url" => VITALS_URL,
                                    "type" => "Observation", "snapshot" => { "element" => elements })
    end

    def vitals(text)
      group = obs_group(VITALS_URL, tests: [%w[patient code category]])
      describe(obs_ig(height_form(text), profiles: [vitals_profile]), group)
    end

    def height(text) = describe(obs_ig(height_form(text)), obs_group)

    def test_modified_code_parameters_give_no_codes
      %w[code:not code:in code:text].each do |param|
        assert_equal 1, height("Observation?#{param}=#{LOINC}|29463-7&patient=x").size, param
        assert_empty @log, param
      end
    end

    def test_token_without_a_code_is_ignored
      assert_equal 1, height("Observation?code=#{LOINC}|&patient=x").size
      assert_empty @log
    end

    def test_category_and_code_from_pattern_coding_and_slices_match
      assert_equal 1, vitals("Observation?code=8302-2&category=vital-signs&patient=x").size
      assert_empty @log
    end

    def test_single_profile_conflict_on_any_shared_parameter_is_unresolved
      assert_empty vitals("Observation?code=#{LOINC}|8302-2&category=laboratory&patient=x")
      assert_equal "Questionnaire usage tracing: unresolved Vitals form query Obs: the Observation profile fixes " \
                   "code=#{LOINC}|8302-2, category=#{CATEGORY}|vital-signs, not code=#{LOINC}|8302-2, " \
                   "category=laboratory\n", @log
    end

    # One item per code, each with its own query named Obs.
    def same_name_items
      %w[8302-2 29463-7].map do |code|
        item("q#{code}", "Item #{code}", query("Obs", "Observation?code=#{LOINC}|#{code}&patient=x"),
             "%Obs.entry.resource.value.value")
      end
    end

    def test_same_name_queries_on_different_items_stay_apart
      groups = [obs_group, obs_group(WEIGHT_URL)]
      profiles = [profile(HEIGHT_URL, "8302-2"), profile(WEIGHT_URL, "29463-7", sliced: true)]
      result = describe(obs_ig(obs_form([], same_name_items), profiles:), *groups)
      lines = groups.map { |group| item_lines(result[group]["obs_search_patient_code"]).grep(/\*\*Item/) }

      assert_equal [["    - **Item 8302-2**: pre-fills the answer; reads value.value\n"],
                    ["    - **Item 29463-7**: pre-fills the answer; reads value.value\n"]], lines
    end
  end
end
