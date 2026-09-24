# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"
require "tmpdir"

module InfernoSuiteGenerator
  class GroupMetadataExtractorUpdateCreateTest < Minitest::Test
    GroupMetadataExtractor = InfernoSuiteGenerator::Generator::GroupMetadataExtractor
    IGResources = InfernoSuiteGenerator::Generator::IGResources
    IGLoader = InfernoSuiteGenerator::Generator::IGLoader

    CS_PROFILE_URL = "http://example.org/CapabilityStatement/server"
    EXPECTATION_URL = "http://hl7.org/fhir/StructureDefinition/capabilitystatement-expectation"

    FakeConfigKeeper = Struct.new(:ig_deps_path, :cs_profile_url, keyword_init: true)

    def setup
      @previous_config_keeper = Registry.get(:config_keeper)
    end

    def teardown
      Registry.register(:config_keeper, @previous_config_keeper)
    end

    def test_update_create_is_true_when_declared_in_capability_statement
      assert_equal true, build_extractor("QuestionnaireResponse").update_create
    end

    def test_update_create_is_false_when_declared_false
      assert_equal false, build_extractor("Observation").update_create
    end

    def test_update_create_defaults_to_false_when_absent
      assert_equal false, build_extractor("Patient").update_create
    end

    def test_update_create_expectation_is_read_from_primitive_extension
      assert_equal "SHALL", build_extractor("QuestionnaireResponse").update_create_expectation
    end

    def test_update_create_expectation_is_resolved_per_resource_type
      assert_equal "SHOULD", build_extractor("Condition").update_create_expectation
    end

    def test_update_create_expectation_ignores_unrelated_extensions
      assert_equal "MAY", build_extractor("Encounter").update_create_expectation
    end

    def test_update_create_expectation_defaults_to_may_without_extension
      assert_equal "MAY", build_extractor("Observation").update_create_expectation
    end

    def test_update_create_expectation_defaults_to_may_without_raw_capability_statement
      cs_hash = capability_statement_hash
      ig_resources = IGResources.new
      ig_resources.add(FHIR.from_contents(cs_hash.to_json))

      extractor = extractor_for(ig_resources, "QuestionnaireResponse")

      assert_equal true, extractor.update_create
      assert_equal "MAY", extractor.update_create_expectation
    end

    def test_update_create_expectation_defaults_to_may_for_auto_detected_resources
      ig_resources = IGResources.new
      resource_capabilities = FHIR::CapabilityStatement::Rest::Resource.new("type" => "Patient")
      extractor = GroupMetadataExtractor.new(resource_capabilities, "http://example.org/p", nil, ig_resources)

      assert_equal false, extractor.update_create
      assert_equal "MAY", extractor.update_create_expectation
    end

    def test_ig_resources_returns_raw_capability_statement_resource_entry
      ig_resources = IGResources.new
      patient_hash = { "resourceType" => "Patient", "id" => "p1" }
      ig_resources.add(FHIR.from_contents(patient_hash.to_json), patient_hash)
      ig_resources.add(FHIR.from_contents(capability_statement_hash.to_json), capability_statement_hash)

      assert_equal "QuestionnaireResponse", ig_resources.raw_cs_resource("QuestionnaireResponse")["type"]
      assert_nil ig_resources.raw_cs_resource("Practitioner")
    end

    def test_ig_loader_preserves_update_create_expectation_from_bundle
      Dir.mktmpdir do |dir|
        bundle = {
          "resourceType" => "Bundle",
          "type" => "collection",
          "entry" => [
            { "resource" => { "resourceType" => "Patient", "id" => "p1" } },
            { "resource" => capability_statement_hash }
          ]
        }
        File.write(File.join(dir, "bundle.json"), bundle.to_json)
        Registry.register(:config_keeper, FakeConfigKeeper.new(ig_deps_path: ".", cs_profile_url: CS_PROFILE_URL))

        ig_resources = nil
        Dir.chdir(dir) { capture_io { ig_resources = IGLoader.new(".").load } }

        extractor = extractor_for(ig_resources, "QuestionnaireResponse")

        assert_equal true, extractor.update_create
        assert_equal "SHALL", extractor.update_create_expectation
      end
    end

    private

    def build_extractor(resource_type)
      ig_resources = IGResources.new
      ig_resources.add(FHIR.from_contents(capability_statement_hash.to_json), capability_statement_hash)
      extractor_for(ig_resources, resource_type)
    end

    def extractor_for(ig_resources, resource_type)
      resource_capabilities = ig_resources.cs_resources.find { |r| r.type == resource_type }
      GroupMetadataExtractor.new(resource_capabilities, "http://example.org/p", nil, ig_resources)
    end

    def expectation_extension(code)
      { "extension" => [{ "url" => EXPECTATION_URL, "valueCode" => code }] }
    end

    def capability_statement_hash
      {
        "resourceType" => "CapabilityStatement",
        "url" => CS_PROFILE_URL,
        "status" => "active",
        "kind" => "requirements",
        "fhirVersion" => "4.0.1",
        "format" => ["json"],
        "rest" => [
          {
            "mode" => "server",
            "resource" => [
              { "type" => "Patient" },
              { "type" => "Observation", "updateCreate" => false },
              {
                "type" => "QuestionnaireResponse",
                "updateCreate" => true,
                "_updateCreate" => expectation_extension("SHALL")
              },
              {
                "type" => "Condition",
                "updateCreate" => true,
                "_updateCreate" => expectation_extension("SHOULD")
              },
              {
                "type" => "Encounter",
                "updateCreate" => true,
                "_updateCreate" => {
                  "extension" => [{ "url" => "http://example.org/other", "valueCode" => "SHALL" }]
                }
              }
            ]
          }
        ]
      }
    end
  end
end
