# frozen_string_literal: true

require_relative "test_helper"
require "fhir_models"
require "inferno_suite_generator/utils/registry"
require "inferno_suite_generator/extractors/ig_metadata_extractor"

module InfernoSuiteGenerator
  class IGMetadataExtractorExtractResourceProfilesTest < Minitest::Test
    IGMetadataExtractor = InfernoSuiteGenerator::Generator::IGMetadataExtractor

    def build_cs_resource(type:, profile: nil, supportedProfile: nil) # rubocop:disable Naming/MethodParameterName
      FHIR::CapabilityStatement::Rest::Resource.new(
        "type" => type,
        "profile" => profile,
        "supportedProfile" => supportedProfile
      )
    end

    class FakeConfigKeeper
      attr_reader :calls

      def initialize(skip_profiles: [])
        @skip_profiles = skip_profiles
        @calls = []
      end

      def skip_metadata_extraction?(profile_url, resource_type)
        @calls << [profile_url, resource_type]
        @skip_profiles.include?(profile_url)
      end
    end

    def setup
      @previous_config_keeper = Registry.get(:config_keeper)
    end

    def teardown
      Registry.register(:config_keeper, @previous_config_keeper)
    end

    def test_returns_supported_profiles_followed_by_the_primary_profile
      cs_resource = build_cs_resource(
        type: "Patient",
        profile: "http://example.org/StructureDefinition/primary",
        supportedProfile: [
          "http://example.org/StructureDefinition/supported-1",
          "http://example.org/StructureDefinition/supported-2"
        ]
      )

      assert_equal(
        [
          "http://example.org/StructureDefinition/supported-1",
          "http://example.org/StructureDefinition/supported-2",
          "http://example.org/StructureDefinition/primary"
        ],
        extract(cs_resource)
      )
    end

    def test_returns_only_the_primary_profile_when_there_are_no_supported_profiles
      cs_resource = build_cs_resource(
        type: "Patient",
        profile: "http://example.org/StructureDefinition/primary",
        supportedProfile: nil
      )

      assert_equal(["http://example.org/StructureDefinition/primary"], extract(cs_resource))
    end

    def test_returns_only_the_supported_profiles_when_there_is_no_primary_profile
      cs_resource = build_cs_resource(
        type: "Patient",
        profile: nil,
        supportedProfile: ["http://example.org/StructureDefinition/supported"]
      )

      assert_equal(["http://example.org/StructureDefinition/supported"], extract(cs_resource))
    end

    def test_returns_an_empty_array_when_the_resource_declares_no_profiles
      cs_resource = build_cs_resource(type: "Patient", profile: nil, supportedProfile: nil)

      assert_empty extract(cs_resource)
    end

    def test_accepts_a_scalar_supported_profile
      cs_resource = build_cs_resource(
        type: "Patient",
        profile: nil,
        supportedProfile: "http://example.org/StructureDefinition/supported"
      )

      assert_equal(["http://example.org/StructureDefinition/supported"], extract(cs_resource))
    end

    def test_strips_the_pipe_delimited_version_from_every_profile
      cs_resource = build_cs_resource(
        type: "Patient",
        profile: "http://example.org/StructureDefinition/primary|2.0.0",
        supportedProfile: ["http://example.org/StructureDefinition/supported|1.2.3"]
      )

      assert_equal(
        [
          "http://example.org/StructureDefinition/supported",
          "http://example.org/StructureDefinition/primary"
        ],
        extract(cs_resource)
      )
    end

    def test_deduplicates_a_profile_listed_as_both_supported_and_primary
      url = "http://example.org/StructureDefinition/shared"
      cs_resource = build_cs_resource(type: "Patient", profile: url, supportedProfile: [url])

      assert_equal([url], extract(cs_resource))
    end

    def test_deduplicates_profiles_that_differ_only_by_version
      cs_resource = build_cs_resource(
        type: "Patient",
        profile: nil,
        supportedProfile: [
          "http://example.org/StructureDefinition/supported|1.0.0",
          "http://example.org/StructureDefinition/supported|2.0.0"
        ]
      )

      assert_equal(["http://example.org/StructureDefinition/supported"], extract(cs_resource))
    end

    def test_rejects_profiles_flagged_for_skipping_by_the_config_keeper
      cs_resource = build_cs_resource(
        type: "Patient",
        profile: "http://example.org/StructureDefinition/primary",
        supportedProfile: [
          "http://example.org/StructureDefinition/skip-me",
          "http://example.org/StructureDefinition/keep-me"
        ]
      )

      assert_equal(
        [
          "http://example.org/StructureDefinition/keep-me",
          "http://example.org/StructureDefinition/primary"
        ],
        extract(cs_resource, skip_profiles: ["http://example.org/StructureDefinition/skip-me"])
      )
    end

    def test_asks_the_config_keeper_about_each_version_stripped_profile_with_the_resource_type
      cs_resource = build_cs_resource(
        type: "Observation",
        profile: "http://example.org/StructureDefinition/primary",
        supportedProfile: ["http://example.org/StructureDefinition/supported|1.2.3"]
      )
      config_keeper = FakeConfigKeeper.new
      extract(cs_resource, config_keeper:)

      assert_equal(
        [
          ["http://example.org/StructureDefinition/supported", "Observation"],
          ["http://example.org/StructureDefinition/primary", "Observation"]
        ],
        config_keeper.calls
      )
    end

    def test_drops_a_blank_profile_string
      cs_resource = build_cs_resource(
        type: "Patient",
        profile: "",
        supportedProfile: ["http://example.org/StructureDefinition/supported"]
      )

      assert_equal(["http://example.org/StructureDefinition/supported"], extract(cs_resource))
    end

    private

    def extract(cs_resource, skip_profiles: [], config_keeper: nil)
      config_keeper ||= FakeConfigKeeper.new(skip_profiles:)
      Registry.register(:config_keeper, config_keeper)
      subject = IGMetadataExtractor.new(ig_resources_double)
      subject.send(:extract_resource_profiles, cs_resource)
    end

    def ig_resources_double
      Object.new.tap do |double|
        def double.cs_resources = []
        def double.profile_structure_definitions = []
      end
    end
  end
end
