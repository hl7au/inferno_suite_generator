# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"
require "inferno_suite_generator/test_modules/patch_test"

module InfernoSuiteGenerator
  # Test double that includes PatchTest and stubs the Inferno runtime dependencies
  # `assert_patch_success` relies on (response, resource, metadata, assertions).
  class TestablePatchTest
    include PatchTest

    attr_reader :metadata, :response, :resource

    def initialize(metadata:, response:, resource:, patch_checks_override: nil)
      @metadata = metadata
      @response = response
      @resource = resource
      @patch_checks_override = patch_checks_override
    end

    def patch_checks
      @patch_checks_override || super
    end

    def assert(condition, message = nil)
      raise Minitest::Assertion, message unless condition
    end
  end

  class PatchTestAssertPatchSuccessTest < Minitest::Test
    def test_passes_when_status_version_and_diff_all_match
      subject = build_subject(
        create_interaction: true, response_status: 200, version_id: "2",
        resource_hash: { "resourceType" => "Patient", "deceasedBoolean" => true }
      )

      subject.send(:assert_patch_success, [{ op: "add", path: "/deceasedBoolean", value: true }])
    end

    def test_fails_status_check_when_response_status_unexpected
      subject = build_subject(create_interaction: true, response_status: 500, version_id: "2",
                              resource_hash: { "resourceType" => "Patient" })

      error = assert_raises(Minitest::Assertion) { subject.send(:assert_patch_success, []) }
      assert_match(/Response status is 500/, error.message)
    end

    def test_fails_version_check_when_create_interaction_present_but_version_not_bumped
      subject = build_subject(create_interaction: true, response_status: 200, version_id: "1",
                              resource_hash: { "resourceType" => "Patient" })

      error = assert_raises(Minitest::Assertion) { subject.send(:assert_patch_success, []) }
      assert_match(/Resource version is 1/, error.message)
    end

    def test_skips_version_check_when_create_interaction_absent
      subject = build_subject(create_interaction: false, response_status: 200, version_id: "1",
                              resource_hash: { "resourceType" => "Patient" })

      subject.send(:assert_patch_success, [])
    end

    def test_fails_diff_check_when_resource_does_not_reflect_patch
      subject = build_subject(create_interaction: true, response_status: 200, version_id: "2",
                              resource_hash: { "resourceType" => "Patient", "deceasedBoolean" => false })

      error = assert_raises(Minitest::Assertion) do
        subject.send(:assert_patch_success, [{ op: "add", path: "/deceasedBoolean", value: true }])
      end
      assert_match(/does not reflect the applied patch/, error.message)
    end

    def test_fails_diff_check_when_removed_value_still_present
      subject = build_subject(create_interaction: true, response_status: 200, version_id: "2",
                              resource_hash: { "resourceType" => "Patient", "deceasedBoolean" => false })

      error = assert_raises(Minitest::Assertion) do
        subject.send(:assert_patch_success, [{ op: "remove", path: "/deceasedBoolean", value: nil }])
      end
      assert_match(/does not reflect the applied patch/, error.message)
    end

    def test_narrowed_checks_skip_version_even_when_create_interaction_present
      subject = build_subject(create_interaction: true, response_status: 200, version_id: "1",
                              resource_hash: { "resourceType" => "Patient" }, patch_checks: %w[status])

      subject.send(:assert_patch_success, [])
    end

    def test_narrowed_checks_skip_diff
      subject = build_subject(create_interaction: true, response_status: 200, version_id: "2",
                              resource_hash: { "resourceType" => "Patient" }, patch_checks: %w[status version])

      subject.send(:assert_patch_success, [{ op: "add", path: "/deceasedBoolean", value: true }])
    end

    private

    def build_subject(create_interaction:, response_status:, version_id:, resource_hash:, patch_checks: nil)
      metadata = Struct.new(:interactions).new(
        create_interaction ? [{ code: "create", expectation: "SHALL" }] : []
      )
      resource = FHIR.from_contents(resource_hash.merge("meta" => { "versionId" => version_id }).to_json)

      TestablePatchTest.new(metadata:, response: { status: response_status }, resource:,
                            patch_checks_override: patch_checks)
    end
  end
end
