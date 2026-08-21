# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator/utils/fhirpath_lab_message_patterns"

module InfernoSuiteGenerator
  class FhirpathLabMessagePatternsTest < Minitest::Test
    def test_every_registered_pattern_defines_the_required_named_captures
      FhirpathLabMessagePatterns::PATTERNS.each do |pattern|
        missing = FhirpathLabMessagePatterns::REQUIRED_CAPTURES - pattern.names
        assert_empty missing, "#{pattern.inspect} is missing required named captures: #{missing.join(", ")}"
      end
    end

    def test_match_returns_nil_when_no_pattern_matches
      assert_nil FhirpathLabMessagePatterns.match("Something went wrong")
    end

    def test_match_returns_nil_for_non_matching_message_without_a_resource_id
      assert_nil FhirpathLabMessagePatterns.match("Patient: some issue: detail")
    end

    # --- JAVA_VALIDATOR_PATTERN ---

    def test_java_validator_pattern_matches_message_without_echoed_resource_type
      message = "Patient/123: Patient.name[0].given: Minimum required = 1, but only found 0"

      match = FhirpathLabMessagePatterns.match(message)

      assert_equal "Patient", match[:resource_type]
      assert_equal "123", match[:resource_id]
      assert_nil match[:echo]
      assert_equal "Patient.name[0].given", match[:path]
      assert_equal "Minimum required = 1, but only found 0", match[:detail]
    end

    def test_java_validator_pattern_matches_message_with_echoed_resource_type_segment
      message = "Patient/pat-sf: Patient: Patient.extension[0]: Internal validator error occurred: " \
                "Could not find value set https://healthterminologies.gov.au/fhir/ValueSet/foo and version null."

      match = FhirpathLabMessagePatterns.match(message)

      assert_equal "Patient", match[:resource_type]
      assert_equal "pat-sf", match[:resource_id]
      assert_equal "Patient", match[:echo]
      assert_equal "Patient.extension[0]", match[:path]
      assert_equal "Internal validator error occurred: " \
                   "Could not find value set https://healthterminologies.gov.au/fhir/ValueSet/foo and version null.",
                   match[:detail]
    end

    def test_java_validator_pattern_treats_bare_type_as_path_when_no_further_segment_follows
      message = "Patient/123: Patient: Minimum required = 1, but only found 0"

      match = FhirpathLabMessagePatterns.match(message)

      assert_nil match[:echo]
      assert_equal "Patient", match[:path]
      assert_equal "Minimum required = 1, but only found 0", match[:detail]
    end

    def test_java_validator_pattern_allows_colon_embedded_in_the_path
      path = "Patient.identifier.where(system='http://hl7.org.au/id/medicare-number').value"
      message = "Patient/123: #{path}: code is invalid"

      match = FhirpathLabMessagePatterns.match(message)

      assert_equal path, match[:path]
      assert_equal "code is invalid", match[:detail]
    end

    def test_java_validator_pattern_preserves_multiline_detail
      message = "Patient/123: Patient.name[0].given: line one\nline two"

      match = FhirpathLabMessagePatterns.match(message)

      assert_equal "line one\nline two", match[:detail]
    end
  end
end
