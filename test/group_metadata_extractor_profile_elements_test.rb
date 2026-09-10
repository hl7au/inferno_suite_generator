# frozen_string_literal: true

require_relative "test_helper"
require "fhir_models"
require "active_support/core_ext/object/blank"
require "inferno_suite_generator/utils/registry"
require "inferno_suite_generator/extractors/group_metadata_extractor"

module InfernoSuiteGenerator
  class GroupMetadataExtractorProfileElementsTest < Minitest::Test
    GroupMetadataExtractor = InfernoSuiteGenerator::Generator::GroupMetadataExtractor

    PROFILE_URL = "http://ex/StructureDefinition/condition"
    PATIENT_PROFILE = "http://ex/StructureDefinition/patient|1.0.0"

    CC = [{ "code" => "CodeableConcept" }].freeze

    SNAPSHOT_ELEMENTS = [
      { "id" => "Condition.clinicalStatus", "path" => "Condition.clinicalStatus", "min" => 1,
        "type" => CC, "binding" => { "strength" => "required" } },
      { "id" => "Condition.category", "path" => "Condition.category", "min" => 0,
        "type" => CC, "binding" => { "strength" => "extensible" } },
      { "id" => "Condition.onset[x]", "path" => "Condition.onset[x]", "min" => 0,
        "type" => [{ "code" => "dateTime" }, { "code" => "CodeableConcept" }],
        "binding" => { "strength" => "required" } },
      { "id" => "Condition.subject", "path" => "Condition.subject", "min" => 1,
        "type" => [{ "code" => "Reference", "targetProfile" => [PATIENT_PROFILE] }] },
      { "id" => "Condition.code", "path" => "Condition.code", "min" => 1, "type" => CC }
    ].freeze

    def setup
      @previous_config_keeper = Registry.get(:config_keeper)
      Registry.register(:config_keeper, Object.new)
    end

    def teardown
      Registry.register(:config_keeper, @previous_config_keeper)
    end

    def profile
      FHIR::StructureDefinition.new(
        "url" => PROFILE_URL, "type" => "Condition",
        "snapshot" => { "element" => SNAPSHOT_ELEMENTS }
      )
    end

    def build_extractor(resource_type: "Condition")
      resource_capabilities = FHIR::CapabilityStatement::Rest::Resource.new("type" => resource_type)
      GroupMetadataExtractor.new(resource_capabilities, PROFILE_URL, nil, ig_resources_double)
    end

    def ig_resources_double
      the_profile = profile
      Object.new.tap do |double|
        double.define_singleton_method(:profile_by_url) { |_url| the_profile }
        double.define_singleton_method(:resource_for_profile) do |url|
          url.include?("patient") ? "Patient" : nil
        end
      end
    end

    def test_mandatory_elements_are_the_element_paths_with_positive_min
      assert_equal(
        %w[Condition.clinicalStatus Condition.subject Condition.code],
        build_extractor.mandatory_elements
      )
    end

    def test_required_concepts_are_codeable_concepts_with_a_required_binding
      assert_equal(%w[clinicalStatus onsetCodeableConcept], build_extractor.required_concepts)
    end

    def test_required_concepts_is_empty_for_observation
      assert_empty build_extractor(resource_type: "Observation").required_concepts
    end

    def test_references_carry_target_profiles_and_resolved_resource_types
      assert_equal(
        [{ path: "Condition.subject", profiles: [PATIENT_PROFILE], resource_types: ["Patient"] }],
        build_extractor.references
      )
    end
  end
end
