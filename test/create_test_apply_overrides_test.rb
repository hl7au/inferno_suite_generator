# frozen_string_literal: true

require_relative "test_helper"
require "date"
require "inferno_suite_generator"
require "inferno_suite_generator/test_modules/create_test"

module InfernoSuiteGenerator
  class CreateTestApplyOverridesTest < Minitest::Test
    class TestableCreateTest
      include CreateTest

      attr_reader :metadata, :references_keeper

      def initialize(metadata:, overrides: {})
        @metadata = metadata
        @references_keeper = Struct.new(:references) do
          def references_for_resource_type(_type) = []
        end.new({})
        @overrides = overrides
      end

      def create_resource_overrides
        @overrides
      end

      def evaluate_fhirpath(resource:, path:)
        []
      end
    end

    def test_returns_resource_unchanged_when_no_overrides
      resource = FHIR::MedicationStatement.new(
        "resourceType" => "MedicationStatement",
        "status" => "active",
        "dateAsserted" => "2000-01-01"
      )
      subject = TestableCreateTest.new(metadata: metadata_double, overrides: {})

      result = subject.send(:apply_create_overrides, resource)

      assert_equal "2000-01-01", result.dateAsserted
    end

    def test_applies_static_override
      resource = FHIR::MedicationStatement.new(
        "resourceType" => "MedicationStatement",
        "status" => "active",
        "dateAsserted" => "2000-01-01"
      )
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        overrides: { "dateAsserted" => "2025-06-01" }
      )

      result = subject.send(:apply_create_overrides, resource)

      assert_equal "2025-06-01", result.dateAsserted
    end

    def test_applies_time_now_token
      resource = FHIR::MedicationStatement.new(
        "resourceType" => "MedicationStatement",
        "status" => "active",
        "dateAsserted" => "2000-01-01"
      )
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        overrides: { "dateAsserted" => "${Time.now}" }
      )

      result = subject.send(:apply_create_overrides, resource)

      assert_equal Date.today.iso8601, result.dateAsserted
    end

    def test_applies_datetime_now_token
      resource = FHIR::MedicationStatement.new(
        "resourceType" => "MedicationStatement",
        "status" => "active",
        "dateAsserted" => "2000-01-01"
      )
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        overrides: { "dateAsserted" => "${DateTime.now}" }
      )

      result = subject.send(:apply_create_overrides, resource)

      assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\z/, result.dateAsserted)
    end

    def test_applies_multiple_overrides
      resource = FHIR::MedicationStatement.new(
        "resourceType" => "MedicationStatement",
        "status" => "active",
        "dateAsserted" => "2000-01-01"
      )
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        overrides: { "dateAsserted" => "${Time.now}", "status" => "completed" }
      )

      result = subject.send(:apply_create_overrides, resource)

      assert_equal Date.today.iso8601, result.dateAsserted
      assert_equal "completed", result.status
    end

    def test_does_not_mutate_original_resource
      resource = FHIR::MedicationStatement.new(
        "resourceType" => "MedicationStatement",
        "status" => "active",
        "dateAsserted" => "2000-01-01"
      )
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        overrides: { "dateAsserted" => "${Time.now}" }
      )

      subject.send(:apply_create_overrides, resource)

      assert_equal "2000-01-01", resource.dateAsserted, "original resource must not be mutated"
    end

    private

    def metadata_double
      Struct.new(:references, :profile_url).new([], "http://example.org/profile")
    end
  end
end
