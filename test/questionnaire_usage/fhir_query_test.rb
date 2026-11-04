# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Verifies what `FhirQuery` reads from an x-fhir-query.
    class FhirQueryTest < Minitest::Test
      LOINC = "http://loinc.org"

      def test_it_shows_as_the_text_it_was_made_from
        assert_equal "Patient?family=x", FhirQuery.new("Patient?family=x").to_s
      end

      def test_the_type_of_a_search_read_and_compartment_search
        assert_equal "Observation", FhirQuery.new("Observation?code=1").resource_type
        assert_equal "Patient", FhirQuery.new("Patient/{{%patient.id}}").resource_type
        assert_equal "Observation", FhirQuery.new("Patient/{{%patient.id}}/Observation?code=1").resource_type
      end

      def test_without_a_known_type_the_type_is_the_last_segment
        query = FhirQuery.new("Unknown/thing?code=1")

        assert_equal "thing", query.resource_type
        refute_predicate query, :read?
      end

      def test_a_read_has_an_id_after_its_type
        assert_predicate FhirQuery.new("Patient/{{%patient.id}}"), :read?
        refute_predicate FhirQuery.new("Patient?family=x"), :read?
        refute_predicate FhirQuery.new("Patient/_search?family=x"), :read?
        refute_predicate FhirQuery.new("Patient/{{%patient.id}}/Observation?code=x"), :read?
      end

      def test_an_operation_is_not_a_read
        refute_predicate FhirQuery.new("Patient/{{%patient.id}}/$everything"), :read?
        refute_predicate FhirQuery.new("Observation/$lastn?code=1"), :read?
        assert_equal "Patient", FhirQuery.new("Patient/{{%patient.id}}/$everything").resource_type
        assert_equal "Observation", FhirQuery.new("Observation/$lastn?code=1").resource_type
      end

      def test_an_ampersand_inside_a_template_does_not_split_the_parameters
        query = FhirQuery.new("Observation?patient={{'Patient/' & %patient.id}}&code=1")

        assert_equal %w[patient code], query.search_params
      end

      def test_search_params_leave_out_modifiers_and_what_only_shapes_the_result
        query = FhirQuery.new("Patient?gender:not=male&family=x&_sort=-birthdate&_count=1&_include=Patient:link")

        assert_equal %w[gender family], query.search_params
      end

      def test_a_compartment_search_selects_by_its_compartment
        assert_equal %w[patient code], FhirQuery.new("Patient/{{%patient.id}}/Observation?code=x").search_params
      end

      def test_includes_are_the_plain_includes_of_the_query_own_type
        query = FhirQuery.new("PractitionerRole?_id=1&_include=PractitionerRole:location" \
                              "&_include:iterate=Location:organization&_include=Location:partof")

        assert_equal ["PractitionerRole:location"], query.includes
        assert_equal [%w[_include:iterate Location:organization], %w[_include Location:partof]], query.other_includes
      end

      def test_codes_have_a_system_when_the_value_does_and_a_comma_means_or
        query = FhirQuery.new("Observation?code=#{LOINC}|8302-2,8306-3&_sort=-date&category=vital-signs")

        assert_equal({ code: [{ system: LOINC, code: "8302-2" }, { system: nil, code: "8306-3" }],
                       category: [{ system: nil, code: "vital-signs" }] }, query.codes)
      end

      def test_codes_skip_templated_values
        query = FhirQuery.new("Observation?code={{%codes}}&patient={{%patient.id}}")

        assert_equal({ code: [], category: [] }, query.codes)
      end

      def test_values_are_decoded_and_a_bad_encoding_is_kept_as_it_is
        encoded = FhirQuery.new("Observation?code=http%3A%2F%2Floinc.org%7C1")

        assert_equal [{ system: LOINC, code: "1" }], encoded.codes[:code]
        assert_equal [{ system: nil, code: "50%" }], FhirQuery.new("Observation?code=50%").codes[:code]
      end
    end
  end
end
