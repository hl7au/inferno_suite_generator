# frozen_string_literal: true

require_relative "test_helper"
require "jsonpath"
require "inferno_suite_generator"
require "inferno_suite_generator/test_modules/create_test"

module InfernoSuiteGenerator
  class CreateTestUpdateResourceByReferencesTest < Minitest::Test
    # Test double that includes CreateTest and provides metadata + references_keeper.
    # Defines evaluate_fhirpath for unit tests (normally provided by Inferno runtime).
    class TestableCreateTest
      include CreateTest

      attr_reader :metadata, :references_keeper

      def initialize(metadata:, references_keeper:)
        @metadata = metadata
        @references_keeper = references_keeper
      end

      # Stub for Inferno's evaluate_fhirpath: path is considered present if it exists in the
      # resource or is a valid settable path (so references can be set at missing optional paths).
      def evaluate_fhirpath(resource:, path:)
        matches = JsonPath.new("$.#{path}").on(resource.to_hash)
        return matches if matches.present?

        # Path not in hash yet; treat as present if parent structure exists (path is settable).
        settable?(resource.to_hash, path) ? [true] : []
      end

      def settable?(hash, path)
        segs = path.split(".")
        cur = hash
        segs[0..-2].each do |seg|
          key, idx = seg.include?("[") ? seg.split(/\[|\]/) : [seg, nil]
          return false unless cur.is_a?(Hash) && cur.key?(key)
          cur = cur[key]
          cur = cur[idx.to_i] if idx && cur.is_a?(Array)
        end
        true
      end
    end

    def test_returns_resource_unchanged_when_no_references
      resource = FHIR::Observation.new(
        "resourceType" => "Observation",
        "status" => "final",
        "code" => { "coding" => [{ "code" => "test" }] }
      )
      metadata = metadata_double(references: [])
      keeper = references_keeper_double({})
      subject = TestableCreateTest.new(metadata: metadata, references_keeper: keeper)

      result = subject.send(:update_resource_by_references, resource)

      assert_equal "Observation", result.resourceType
      assert_equal "final", result.status
      assert_equal "test", result.code.coding.first.code
      assert_nil result.subject
    end

    def test_sets_reference_at_path_when_reference_and_id_present
      resource = FHIR::Observation.new(
        "resourceType" => "Observation",
        "status" => "final",
        "code" => { "coding" => [{ "code" => "test" }] }
      )
      metadata = metadata_double(references: [
                                   { path: "subject", resource_types: ["Patient"] }
                                 ])
      keeper = references_keeper_double("Patient" => ["patient-123"])
      subject = TestableCreateTest.new(metadata: metadata, references_keeper: keeper)

      result = subject.send(:update_resource_by_references, resource)

      assert result.subject.is_a?(FHIR::Reference)
      assert_equal "Patient/patient-123", result.subject.reference
    end

    def test_skips_path_when_resource_types_empty
      resource = FHIR::Observation.new(
        "resourceType" => "Observation",
        "status" => "final"
      )
      metadata = metadata_double(references: [
                                   { path: "subject", resource_types: [] }
                                 ])
      keeper = references_keeper_double({})
      subject = TestableCreateTest.new(metadata: metadata, references_keeper: keeper)

      result = subject.send(:update_resource_by_references, resource)

      assert_nil result.subject
    end

    def test_skips_path_when_references_keeper_has_no_id_for_resource_type
      resource = FHIR::Observation.new(
        "resourceType" => "Observation",
        "status" => "final"
      )
      metadata = metadata_double(references: [
                                   { path: "subject", resource_types: ["Patient"] }
                                 ])
      keeper = references_keeper_double("Patient" => []) # no ids
      subject = TestableCreateTest.new(metadata: metadata, references_keeper: keeper)

      result = subject.send(:update_resource_by_references, resource)

      assert_nil result.subject
    end

    def test_sets_multiple_reference_paths
      resource = FHIR::DeviceRequest.new(
        "resourceType" => "DeviceRequest",
        "status" => "active"
      )
      metadata = metadata_double(references: [
                                   { path: "subject", resource_types: ["Patient"] },
                                   { path: "performer", resource_types: ["Practitioner"] }
                                 ])
      keeper = references_keeper_double(
        "Patient" => ["p1"],
        "Practitioner" => ["pr1"]
      )
      subject = TestableCreateTest.new(metadata: metadata, references_keeper: keeper)

      result = subject.send(:update_resource_by_references, resource)

      assert_equal "Patient/p1", result.subject.reference
      assert_equal "Practitioner/pr1", result.performer.reference
    end

    def test_does_not_mutate_original_resource
      resource = FHIR::Observation.new(
        "resourceType" => "Observation",
        "status" => "final"
      )
      metadata = metadata_double(references: [
                                   { path: "subject", resource_types: ["Patient"] }
                                 ])
      keeper = references_keeper_double("Patient" => ["patient-123"])
      subject = TestableCreateTest.new(metadata: metadata, references_keeper: keeper)

      subject.send(:update_resource_by_references, resource)

      assert_nil resource.subject, "original resource must not be mutated"
    end

    def test_uses_first_reference_when_same_path_appears_multiple_times
      resource = FHIR::Observation.new("resourceType" => "Observation", "status" => "final")
      metadata = metadata_double(references: [
                                   { path: "subject", resource_types: ["Patient"] },
                                   { path: "subject", resource_types: ["Group"] }
                                 ])
      keeper = references_keeper_double("Patient" => ["p1"], "Group" => ["g1"])
      subject = TestableCreateTest.new(metadata: metadata, references_keeper: keeper)

      result = subject.send(:update_resource_by_references, resource)

      # First matching reference (Patient) is used
      assert_equal "Patient/p1", result.subject.reference
    end

    def test_sets_nested_path
      resource = FHIR::Observation.new(
        "resourceType" => "Observation",
        "status" => "final",
        "hasMember" => []
      )
      metadata = metadata_double(references: [
                                   { path: "hasMember[0]", resource_types: ["Observation"] }
                                 ])
      keeper = references_keeper_double("Observation" => ["obs-1"])
      subject = TestableCreateTest.new(metadata: metadata, references_keeper: keeper)

      result = subject.send(:update_resource_by_references, resource)

      assert result.hasMember.first.is_a?(FHIR::Reference)
      assert_equal "Observation/obs-1", result.hasMember.first.reference
    end

    private

    def metadata_double(references:)
      Struct.new(:references).new(references)
    end

    def references_keeper_double(refs_by_type)
      refs = refs_by_type.transform_values(&:dup)
      Struct.new(:refs) do
        def references_for_resource_type(resource_type)
          refs[resource_type] || []
        end
      end.new(refs)
    end
  end
end
