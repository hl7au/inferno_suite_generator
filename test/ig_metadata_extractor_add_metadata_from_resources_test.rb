# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  class IGMetadataExtractorAddMetadataFromResourcesTest < Minitest::Test
    GroupMetadata = InfernoSuiteGenerator::Generator::GroupMetadata
    GroupMetadataExtractor = InfernoSuiteGenerator::Generator::GroupMetadataExtractor
    IGMetadataExtractor = InfernoSuiteGenerator::Generator::IGMetadataExtractor

    FakeExtractorResult = Struct.new(:group_metadata)

    class FakeConfigKeeper
      def initialize(skip_profiles: [])
        @skip_profiles = skip_profiles
      end

      def skip_metadata_extraction?(profile_url, _resource_type)
        @skip_profiles.include?(profile_url)
      end
    end

    class FakeIGResources
      def initialize(cs_resources)
        @cs_resources = cs_resources
      end

      attr_reader :cs_resources
    end

    def setup
      @previous_config_keeper = Registry.get(:config_keeper)
      @calls = []
      @raising_profiles = []
    end

    def teardown
      Registry.register(:config_keeper, @previous_config_keeper)
    end

    def test_builds_a_group_for_each_supported_profile_and_the_primary_profile
      resource = fhir_resource(
        type: "Patient",
        profile: "http://example.org/StructureDefinition/primary",
        supportedProfile: [
          "http://example.org/StructureDefinition/supported-1",
          "http://example.org/StructureDefinition/supported-2"
        ]
      )
      subject = build_subject([resource])

      with_stubbed_extractor do
        subject.add_metadata_from_resources
      end

      assert_equal(
        [
          "http://example.org/StructureDefinition/supported-1",
          "http://example.org/StructureDefinition/supported-2",
          "http://example.org/StructureDefinition/primary"
        ],
        subject.metadata.groups.map(&:profile_url)
      )
    end

    def test_strips_pipe_delimited_version_from_supported_profile_before_extraction
      resource = fhir_resource(
        type: "Patient",
        profile: nil,
        supportedProfile: ["http://example.org/StructureDefinition/supported|1.2.3"]
      )
      subject = build_subject([resource])

      with_stubbed_extractor do
        subject.add_metadata_from_resources
      end

      assert_equal(
        ["http://example.org/StructureDefinition/supported"],
        @calls.map { |call| call[:profile_url] }
      )
    end

    def test_orders_all_supported_profile_groups_before_any_primary_profile_groups
      resource_a = fhir_resource(
        type: "Patient",
        profile: "http://example.org/StructureDefinition/primary-a",
        supportedProfile: ["http://example.org/StructureDefinition/supported-a"]
      )
      resource_b = fhir_resource(
        type: "Observation",
        profile: "http://example.org/StructureDefinition/primary-b",
        supportedProfile: ["http://example.org/StructureDefinition/supported-b"]
      )
      subject = build_subject([resource_a, resource_b])

      with_stubbed_extractor do
        subject.add_metadata_from_resources
      end

      assert_equal(
        [
          "http://example.org/StructureDefinition/supported-a",
          "http://example.org/StructureDefinition/supported-b",
          "http://example.org/StructureDefinition/primary-a",
          "http://example.org/StructureDefinition/primary-b"
        ],
        subject.metadata.groups.map(&:profile_url)
      )
    end

    def test_skips_supported_profile_flagged_by_config_keeper
      resource = fhir_resource(
        type: "Patient",
        profile: nil,
        supportedProfile: [
          "http://example.org/StructureDefinition/skip-me",
          "http://example.org/StructureDefinition/keep-me"
        ]
      )
      subject = build_subject(
        [resource],
        config_keeper: FakeConfigKeeper.new(skip_profiles: ["http://example.org/StructureDefinition/skip-me"])
      )

      with_stubbed_extractor do
        subject.add_metadata_from_resources
      end

      assert_equal(
        ["http://example.org/StructureDefinition/keep-me"],
        subject.metadata.groups.map(&:profile_url)
      )
    end

    def test_skips_primary_profile_flagged_by_config_keeper
      resource = fhir_resource(
        type: "Patient",
        profile: "http://example.org/StructureDefinition/skip-me",
        supportedProfile: nil
      )
      subject = build_subject(
        [resource],
        config_keeper: FakeConfigKeeper.new(skip_profiles: ["http://example.org/StructureDefinition/skip-me"])
      )

      with_stubbed_extractor do
        subject.add_metadata_from_resources
      end

      assert_empty subject.metadata.groups
      assert_empty @calls
    end

    def test_skips_primary_profile_when_blank
      resource = fhir_resource(type: "Patient", profile: nil, supportedProfile: nil)
      subject = build_subject([resource])

      with_stubbed_extractor do
        subject.add_metadata_from_resources
      end

      assert_empty subject.metadata.groups
      assert_empty @calls
    end

    def test_tolerates_resource_with_no_supported_profiles
      resource = fhir_resource(
        type: "Patient",
        profile: "http://example.org/StructureDefinition/primary",
        supportedProfile: nil
      )
      subject = build_subject([resource])

      with_stubbed_extractor do
        subject.add_metadata_from_resources
      end

      assert_equal(
        ["http://example.org/StructureDefinition/primary"],
        subject.metadata.groups.map(&:profile_url)
      )
    end

    def test_recovers_from_error_extracting_a_supported_profile_and_keeps_other_groups
      resource = fhir_resource(
        type: "Patient",
        profile: "http://example.org/StructureDefinition/primary",
        supportedProfile: [
          "http://example.org/StructureDefinition/broken",
          "http://example.org/StructureDefinition/fine"
        ]
      )
      subject = build_subject([resource])
      @raising_profiles = ["http://example.org/StructureDefinition/broken"]

      _, stderr = capture_io do
        with_stubbed_extractor do
          subject.add_metadata_from_resources
        end
      end

      assert_equal(
        [
          "http://example.org/StructureDefinition/fine",
          "http://example.org/StructureDefinition/primary"
        ],
        subject.metadata.groups.map(&:profile_url)
      )
      assert_match(
        /Error extracting metadata for supported profile http:\/\/example\.org\/StructureDefinition\/broken of resource Patient: boom/,
        stderr
      )
    end

    def test_recovers_from_error_extracting_the_primary_profile_and_keeps_other_groups
      resource = fhir_resource(
        type: "Patient",
        profile: "http://example.org/StructureDefinition/broken",
        supportedProfile: ["http://example.org/StructureDefinition/fine"]
      )
      subject = build_subject([resource])
      @raising_profiles = ["http://example.org/StructureDefinition/broken"]

      _, stderr = capture_io do
        with_stubbed_extractor do
          subject.add_metadata_from_resources
        end
      end

      assert_equal(
        ["http://example.org/StructureDefinition/fine"],
        subject.metadata.groups.map(&:profile_url)
      )
      assert_match(
        /Error extracting metadata for profile http:\/\/example\.org\/StructureDefinition\/broken of resource Patient: boom/,
        stderr
      )
    end

    def test_postprocesses_groups_with_the_ig_resources
      resource = fhir_resource(
        type: "Patient",
        profile: "http://example.org/StructureDefinition/primary",
        supportedProfile: nil
      )
      ig_resources = FakeIGResources.new([resource])
      subject = build_subject([resource], ig_resources:)

      with_stubbed_extractor do
        subject.add_metadata_from_resources
      end

      # delayed_references is populated by IGMetadata#postprocess_groups, which
      # only runs after metadata.groups has been assigned.
      refute_nil subject.metadata.groups.first.delayed_references
    end

    private

    def fhir_resource(type:, profile:, supportedProfile:) # rubocop:disable Naming/MethodParameterName
      FHIR::CapabilityStatement::Rest::Resource.new(
        "type" => type,
        "profile" => profile,
        "supportedProfile" => supportedProfile
      )
    end

    def build_subject(cs_resources, config_keeper: FakeConfigKeeper.new, ig_resources: nil)
      Registry.register(:config_keeper, config_keeper)
      IGMetadataExtractor.new(ig_resources || FakeIGResources.new(cs_resources))
    end

    def with_stubbed_extractor(&block)
      factory = lambda do |resource_capabilities, profile_url, _ig_metadata, _ig_resources|
        @calls << { resource: resource_capabilities, profile_url: profile_url }
        raise "boom" if @raising_profiles.include?(profile_url)

        group = GroupMetadata.new(
          name: "group_for_#{profile_url}",
          resource: "Patient",
          profile_url: profile_url,
          searches: [],
          references: []
        )
        FakeExtractorResult.new(group)
      end

      GroupMetadataExtractor.stub(:new, factory, &block)
    end
  end
end
