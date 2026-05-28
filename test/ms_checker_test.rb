# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"
require "ostruct"
require "inferno_suite_generator/test_utils/ms_checker"
require "fhir_models"
require "json"
require "fileutils"

module InfernoSuiteGenerator
  class MSCheckerTest < Minitest::Test
    Extension = Struct.new(:url)
    ElementWithExtension = Struct.new(:extension)
    TestMetadata = Struct.new(:mandatory_elements, :resource, :must_supports)
    # rubocop:disable Naming/MethodName -- doubles mirror FHIR JSON field names used by FHIRResourceNavigation
    ResourceWithValueString = Struct.new(:valueString)
    ResourceWithUnderscoreValueString = Struct.new(:_valueString)
    ResourceWithPrimitiveSourceHash = Struct.new(:valueString, :source_hash)
    # rubocop:enable Naming/MethodName

    def test_dar_found_true_when_value_has_dar_extension
      checker = build_checker
      resource = ResourceWithValueString.new(
        ElementWithExtension.new([Extension.new(FHIRResourceNavigation::DAR_EXTENSION_URL)])
      )

      assert checker.send(:dar_found?, resource, "valueString")
    end

    def test_dar_found_true_when_primitive_fallback_returns_true
      checker = build_checker

      checker.stub(:find_a_value_at, nil) do
        checker.stub(:primitive_dar_found?, true) do
          assert checker.send(:dar_found?, Object.new, "valueString")
        end
      end
    end

    def test_dar_found_true_for_underscore_primitive_extension_path
      checker = build_checker
      primitive_extension = ElementWithExtension.new([Extension.new(FHIRResourceNavigation::DAR_EXTENSION_URL)])
      resource = ResourceWithUnderscoreValueString.new(primitive_extension)

      assert checker.send(:dar_found?, resource, "valueString")
    end

    def test_dar_found_false_when_no_dar_value_and_no_primitive_dar
      checker = build_checker

      checker.stub(:find_a_value_at, nil) do
        checker.stub(:primitive_dar_found?, false) do
          refute checker.send(:dar_found?, Object.new, "valueString")
        end
      end
    end

    def test_dar_found_true_when_primitive_extension_is_only_in_source_hash
      checker = build_checker
      resource = primitive_source_hash_resource

      assert checker.send(:dar_found?, resource, "valueString")
    end

    def test_independence_from_position_in_array
      resource = fixture_to_resource("test/fixtures/observation.json", FHIR::Observation)
      metadata = fixture_to_ostruct("test/fixtures/metadata.json")
      ms_checker = MSChecker.new(metadata)
      result = ms_checker.elements_present_statuses([resource])

      all_exists = result.all? { |result| result[:present] == true }
      missing_elements = result.select { |result| result[:present] == false }.map { |result| result[:path] }

      assert all_exists, "Expected all elements to be present, but missing #{missing_elements.count} items: #{missing_elements.join(', ')}"
    end

    private

    def fixture_to_ostruct(fixture_path)
      OpenStruct.new(json_to_hash(fixture_path))
    end

    def fixture_to_resource(fixture_path, model_class)
      model_class.new(json_to_hash(fixture_path, symbolize_names: false))
    end

    def json_to_hash(file_path, symbolize_names: true)
      json_string = File.read(file_path)
      JSON.parse(json_string, symbolize_names:)
    end

    def primitive_source_hash_resource
      ResourceWithPrimitiveSourceHash.new(
        "unknown",
        "_valueString" => {
          "extension" => [{ "url" => FHIRResourceNavigation::DAR_EXTENSION_URL }]
        }
      )
    end

    def build_checker
      metadata = TestMetadata.new([], "Observation", { elements: [] })
      MSChecker.new(metadata)
    end
  end
end
