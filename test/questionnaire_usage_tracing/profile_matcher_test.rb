# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # Verifies `ProfileMatcher` builds its input from queries.
    class ProfileMatcherInputTest < Minitest::Test
      include ProfileMatcherFixtures

      def test_from_query_reads_codes_with_and_without_system
        input = ProfileMatcher.from_query("Observation?code=#{LOINC}|8302-2,8306-3&_sort=-date&category=vital-signs")

        assert_equal "Observation", input[:resource_type]
        assert_equal({ code: [{ system: LOINC, code: "8302-2" }, { system: nil, code: "8306-3" }],
                       category: [{ system: nil, code: "vital-signs" }] }, input[:codes])
      end

      def test_from_query_skips_templated_values
        input = ProfileMatcher.from_query("Observation?code={{%codes}}&patient={{%patient.id}}")

        assert_equal({ code: [], category: [] }, input[:codes])
      end
    end

    # Verifies `ProfileMatcher` picks the groups a source links to, from the
    # resource type and the `code` and `category` values the profiles fix.
    class ProfileMatcherTest < Minitest::Test
      include ProfileMatcherFixtures

      def test_one_group_matches_by_resource_type
        matcher = matcher_for(BODY_HEIGHT => body_height)

        assert_equal({ groups: [BODY_HEIGHT], matched_by: "resource_type" },
                     match_urls(matcher, "Observation?code=8302-2"))
      end

      def test_the_profile_with_the_queried_code_wins
        matcher = matcher_for(observation_profiles)

        assert_equal({ groups: [BODY_HEIGHT], matched_by: "code" }, match_urls(matcher, "Observation?code=8302-2"))
        assert_equal({ groups: [BODY_WEIGHT], matched_by: "code" },
                     match_urls(matcher, "Observation?code=#{LOINC}|29463-7"))
      end

      def test_profile_codes_reads_fixed_code_slices_with_their_system
        matcher = matcher_for(BODY_WEIGHT => body_weight)
        group = Generator::GroupMetadata.new(resource: "Observation", profile_url: BODY_WEIGHT)

        assert_equal({ code: [{ system: LOINC, code: "29463-7" }],
                       category: [{ system: OBSERVATION_CATEGORY, code: "vital-signs" }] },
                     matcher.profile_codes(group))
      end

      def test_a_category_query_matches_every_profile_with_that_category
        matcher = matcher_for(observation_profiles)

        assert_output(/matches several profiles/) do
          assert_equal({ groups: [BODY_HEIGHT, BODY_WEIGHT], matched_by: "code" },
                       match_urls(matcher, "Observation?category=vital-signs"))
        end
      end

      def test_a_code_that_no_profile_has_is_unresolved
        matcher = matcher_for(observation_profiles)

        assert_output(/unresolved Observation: no Observation profile matches code=1234-5/) do
          assert_nil match_urls(matcher, "Observation?code=1234-5")
        end
      end

      def test_a_code_with_another_system_is_unresolved
        matcher = matcher_for(observation_profiles)

        assert_output(/unresolved/) { assert_nil match_urls(matcher, "Observation?code=#{SNOMED}|8302-2") }
      end

      def test_a_type_without_a_group_is_untraced
        matcher = matcher_for(BODY_HEIGHT => body_height)

        assert_output(/untraced GP CCMP ObsBloodPressure: no group for Condition/) do
          assert_nil matcher.match("Condition", context: "GP CCMP ObsBloodPressure")
        end
      end

      def test_any_of_type_matches_every_group_of_the_type
        matcher = matcher_for(AU_CORE_PATIENT => profile("Patient"), AU_BASE_PATIENT => profile("Patient"))
        result = matcher.match("Patient", any_of_type: true)

        assert_equal [AU_CORE_PATIENT, AU_BASE_PATIENT], result[:groups].map(&:profile_url)
        assert_equal "resource_type", result[:matched_by]
      end

      def test_a_template_matches_by_its_code_coding
        matcher = matcher_for(observation_profiles)
        template = {
          "resourceType" => "Observation",
          "id" => "BodyHeightTemplate",
          "code" => { "coding" => [{ "system" => LOINC, "code" => "8302-2" },
                                   { "system" => SNOMED, "code" => "50373000" }] }
        }
        input = ProfileMatcher.from_template(template)

        result = matcher.match(input[:resource_type], codes: input[:codes])

        assert_equal [BODY_HEIGHT], result[:groups].map(&:profile_url)
      end
    end
  end
end
