# frozen_string_literal: true

require_relative "questionnaire_usage_query_helpers"

module InfernoSuiteGenerator
  # Matching queries to profiles by code, and the "Not tested by this group" comparison lines.
  class QuestionnaireUsageQueryMatchingTest < Minitest::Test
    include QuestionnaireUsageQueryHelpers

    def untested_line(group)
      not_tested(describe(obs_ig(height_form(COMPARTMENT_QUERY)), group).fetch(group))
    end

    def compared(line)
      query_block("searches Observation resources", COMPARTMENT_QUERY, "    - #{line}\n", HEIGHT_ITEM)
    end

    def test_untested_search_with_the_same_group_searches_says_it_has_no_test
      assert_equal compared("This group searches by the same parameters, patient + code + date, but has no test " \
                            "for it"), untested_line(obs_group(searches: [%w[code patient date]], tests: []))
    end

    def test_untested_search_lists_the_group_searches_not_the_recorded_tests
      group = obs_group(searches: [%w[status patient], %w[_id]], tests: [%w[patient]])

      assert_equal compared("A search by patient + code + date; this group tests status + patient, _id"),
                   untested_line(group)
    end

    def test_untested_search_without_group_searches_has_no_tail
      assert_equal compared("A search by patient + code + date"),
                   untested_line(obs_group(searches: [], tests: [%w[_id]]))
    end

    def test_summary_label_uses_the_recorded_test_order
      group = obs_group(tests: [%w[date code patient]])
      entry = describe(obs_ig(height_form(COMPARTMENT_QUERY)), group).fetch(group)

      assert_includes entry[:group],
                      "- **Vitals form**: see the search by date + code + patient and Must Support tests\n"
      assert_nil not_tested(entry)
    end

    def test_query_without_search_parameters_has_no_test_and_no_comparison
      group = obs_group
      untested = not_tested(describe(obs_ig(height_form("Observation?_count=1")), group).fetch(group))

      assert_equal query_block("searches Observation resources", "Observation?_count=1", HEIGHT_ITEM), untested
    end

    def two_profiles(text)
      height = obs_group
      weight = obs_group(WEIGHT_URL)
      result = describe(obs_ig(height_form(text), profiles: [profile(HEIGHT_URL, "8302-2"),
                                                             profile(WEIGHT_URL, "29463-7", sliced: true)]),
                        height, weight)
      result.transform_keys { |group| group.equal?(height) ? :height : :weight }
    end

    def test_several_profiles_keep_only_those_whose_codes_overlap
      assert_equal %i[weight], two_profiles("Observation?code=#{LOINC}|29463-7&patient=x").keys
      assert_empty @log
    end

    def test_several_matching_profiles_are_all_kept_and_logged
      assert_equal %i[height weight], two_profiles("Observation?code=8302-2,#{LOINC}|29463-7&patient=x").keys
      assert_equal "Questionnaire usage tracing: Vitals form query Obs matches several profiles: " \
                   "#{HEIGHT_URL}, #{WEIGHT_URL}\n", @log
    end

    def test_no_matching_profile_is_logged_unresolved
      assert_empty two_profiles("Observation?code=#{LOINC}|9999-9&patient=x")
      assert_equal "Questionnaire usage tracing: unresolved Vitals form query Obs: no Observation profile matches " \
                   "code=#{LOINC}|9999-9\n", @log
    end

    def test_code_the_only_profile_fixes_otherwise_gives_nothing_and_is_logged
      assert_equal({}, describe(obs_ig(height_form("Observation?code=#{LOINC}|29463-7&patient=x")), obs_group))
      assert_equal "Questionnaire usage tracing: unresolved Vitals form query Obs: the Observation profile fixes " \
                   "code=#{LOINC}|8302-2, not code=#{LOINC}|29463-7\n", @log
    end
  end
end
