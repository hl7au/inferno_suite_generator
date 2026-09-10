# frozen_string_literal: true

require_relative "test_helper"
require "fhir_models"
require "active_support/core_ext/object/blank"
require "inferno_suite_generator/utils/registry"
require "inferno_suite_generator/extractors/search_metadata_extractor"

module InfernoSuiteGenerator
  class SearchMetadataExtractorTest < Minitest::Test
    SearchMetadataExtractor = InfernoSuiteGenerator::Generator::SearchMetadataExtractor

    EXPECTATION_EXTENSION_URL =
      "http://hl7.org/fhir/StructureDefinition/capabilitystatement-expectation"
    COMBO_EXTENSION_URL =
      "http://hl7.org/fhir/StructureDefinition/capabilitystatement-search-parameter-combination"

    class FakeConfig
      def search_params_expectation = %w[SHALL SHOULD]
      def search_params_to_ignore = %w[_count _sort]
      def override_search_expectation(*) = nil
    end

    def setup
      @previous_config_keeper = Registry.get(:config_keeper)
      Registry.register(:config_keeper, FakeConfig.new)
    end

    def teardown
      Registry.register(:config_keeper, @previous_config_keeper)
    end

    def search_param(name, expectation)
      FHIR::CapabilityStatement::Rest::Resource::SearchParam.new(
        "name" => name,
        "extension" => [{ "url" => EXPECTATION_EXTENSION_URL, "valueCode" => expectation }]
      )
    end

    def combo_extension(names, expectation)
      FHIR::Extension.new(
        "url" => COMBO_EXTENSION_URL,
        "extension" => names.map { |n| { "url" => "required", "valueString" => n } } +
          [{ "url" => EXPECTATION_EXTENSION_URL, "valueCode" => expectation }]
      )
    end

    def build_extractor(search_params: [], extensions: [])
      resource = FHIR::CapabilityStatement::Rest::Resource.new(
        "type" => "Patient",
        "searchParam" => search_params,
        "extension" => extensions
      )
      SearchMetadataExtractor.new(resource, nil, [], { resource: "Patient", profile_url: "http://example.org/p" })
    end

    def test_basic_searches_are_wrapped_in_a_names_array_with_the_expectation
      extractor = build_extractor(search_params: [search_param("name", "SHALL")])

      assert_equal([{ names: ["name"], expectation: "SHALL" }], extractor.searches)
    end

    def test_search_params_below_the_configured_expectation_are_dropped
      extractor = build_extractor(
        search_params: [search_param("name", "SHALL"), search_param("birthdate", "MAY")]
      )

      assert_equal([{ names: ["name"], expectation: "SHALL" }], extractor.searches)
    end

    def test_ignored_search_params_are_excluded
      extractor = build_extractor(
        search_params: [search_param("name", "SHALL"), search_param("_count", "SHALL")]
      )

      assert_equal([{ names: ["name"], expectation: "SHALL" }], extractor.searches)
    end

    def test_missing_expectation_extension_defaults_to_shall
      param = FHIR::CapabilityStatement::Rest::Resource::SearchParam.new("name" => "name")
      extractor = build_extractor(search_params: [param])

      assert_equal([{ names: ["name"], expectation: "SHALL" }], extractor.searches)
    end

    def test_combo_searches_are_extracted_from_the_combination_extension
      extractor = build_extractor(
        search_params: [search_param("name", "SHALL"), search_param("gender", "SHALL")],
        extensions: [combo_extension(%w[name gender], "SHALL")]
      )

      assert_includes extractor.searches, { names: %w[name gender], expectation: "SHALL" }
    end

    def test_combo_searches_below_the_configured_expectation_are_dropped
      extractor = build_extractor(
        extensions: [combo_extension(%w[name gender], "MAY")]
      )

      assert_empty extractor.searches
    end

    def test_ignored_params_are_stripped_from_combo_searches
      extractor = build_extractor(
        search_params: [search_param("name", "SHALL")],
        extensions: [combo_extension(%w[name _count], "SHALL")]
      )

      refute(extractor.searches.any? { |search| search[:names].include?("_count") })
    end

    def test_non_combination_extensions_are_ignored
      other = FHIR::Extension.new("url" => "http://example.org/other", "valueString" => "x")
      extractor = build_extractor(
        search_params: [search_param("name", "SHALL")],
        extensions: [other]
      )

      assert_equal([{ names: ["name"], expectation: "SHALL" }], extractor.searches)
    end

    def test_no_search_params_yields_no_searches
      assert_empty build_extractor.searches
    end
  end
end
