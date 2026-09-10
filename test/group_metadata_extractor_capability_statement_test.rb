# frozen_string_literal: true

require_relative "test_helper"
require "fhir_models"
require "active_support/core_ext/object/blank"
require "inferno_suite_generator/utils/registry"
require "inferno_suite_generator/extractors/group_metadata_extractor"

module InfernoSuiteGenerator
  class GroupMetadataExtractorCapabilityStatementTest < Minitest::Test
    GroupMetadataExtractor = InfernoSuiteGenerator::Generator::GroupMetadataExtractor

    EXPECTATION_EXTENSION_URL =
      "http://hl7.org/fhir/StructureDefinition/capabilitystatement-expectation"

    def setup
      @previous_config_keeper = Registry.get(:config_keeper)
      Registry.register(:config_keeper, Object.new)
    end

    def teardown
      Registry.register(:config_keeper, @previous_config_keeper)
    end

    def expectation(code)
      [{ "url" => EXPECTATION_EXTENSION_URL, "valueCode" => code }]
    end

    def extractor_for(**resource_fields)
      resource = FHIR::CapabilityStatement::Rest::Resource.new({ "type" => "Patient" }.merge(resource_fields))
      GroupMetadataExtractor.new(resource, "http://example.org/p", nil, nil)
    end

    def test_interactions_resolve_the_expectation_extension_by_url
      extractor = extractor_for(interaction: [
                                  { "code" => "read", "extension" => expectation("SHALL") },
                                  { "code" => "search-type" }
                                ])

      assert_equal(
        [{ code: "read", expectation: "SHALL" }, { code: "search-type", expectation: "SHALL" }],
        extractor.interactions
      )
    end

    def test_operations_resolve_the_expectation_extension_and_tolerate_a_missing_one
      extractor = extractor_for(operation: [
                                  { "name" => "everything", "extension" => expectation("SHOULD") },
                                  { "name" => "validate" }
                                ])

      assert_equal(
        [{ code: "everything", expectation: "SHOULD" }, { code: "validate", expectation: "SHALL" }],
        extractor.operations
      )
    end

    def test_include_params_and_revincludes_default_to_an_empty_array
      extractor = extractor_for

      assert_empty extractor.include_params
      assert_empty extractor.revincludes
    end

    def test_include_params_and_revincludes_are_returned_verbatim
      extractor = extractor_for(
        searchInclude: %w[Patient:general-practitioner Patient:link],
        searchRevInclude: %w[Provenance:target]
      )

      assert_equal %w[Patient:general-practitioner Patient:link], extractor.include_params
      assert_equal %w[Provenance:target], extractor.revincludes
    end
  end
end
