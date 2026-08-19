# frozen_string_literal: true

require_relative "test_helper"
require "active_support/all"
require "inferno_suite_generator/utils/fhirpath_lab_message_linker"

module InfernoSuiteGenerator
  class FhirpathLabMessageLinkerTest < Minitest::Test
    def test_linkify_rewrites_matching_message
      message = "Patient/123: Patient.name[0].given: Minimum required = 1, but only found 0"

      result = linkify(message)

      expected_link = "[Patient.name[0].given](https://fhirpath-lab.com?" \
                      "expression=Patient.name%5B0%5D.given&engine=fhirpath.js&" \
                      "resource=http%3A%2F%2Fkeeper.example%2Fsession-1%2FPatient%2F123)"
      assert_equal "Patient/123: #{expected_link}: Minimum required = 1, but only found 0", result
    end

    def test_linkify_leaves_non_matching_message_untouched
      message = "Something went wrong"
      assert_equal message, linkify(message)
    end

    def test_linkify_leaves_message_untouched_when_base_url_missing
      message = "Patient/123: Patient.name[0].given: detail"
      assert_equal message, linkify(message, base_url: nil)
    end

    def test_linkify_leaves_message_untouched_when_resource_keeper_url_missing
      message = "Patient/123: Patient.name[0].given: detail"
      assert_equal message, linkify(message, resource_keeper_url: nil)
    end

    def test_linkify_leaves_message_untouched_when_session_id_missing
      message = "Patient/123: Patient.name[0].given: detail"
      assert_equal message, linkify(message, session_id: nil)
    end

    def test_linkify_leaves_message_without_resource_id_untouched
      message = "Patient: some issue: detail"
      assert_equal message, linkify(message)
    end

    def test_linkify_preserves_multiline_detail
      message = "Patient/123: Patient.name[0].given: line one\nline two"
      result = linkify(message)
      assert result.end_with?("line one\nline two")
    end

    def test_linkify_returns_non_string_untouched
      assert_nil linkify(nil)
    end

    private

    def linkify(message, base_url: "https://fhirpath-lab.com/", resource_keeper_url: "http://keeper.example",
                session_id: "session-1")
      FhirpathLabMessageLinker.linkify(message, base_url:, resource_keeper_url:, session_id:)
    end
  end

  class MessagesFhirpathLabPatchTest < Minitest::Test
    class FakeSuite
      FHIRPATHLAB_URL = "https://fhirpath-lab.com/"
      RESOURCE_KEEPER_URL = "http://keeper.example"
    end

    class FakeRunnable
      include Inferno::DSL::Messages

      attr_reader :test_session_id

      def initialize(test_session_id: "session-1")
        @test_session_id = test_session_id
      end

      def self.suite
        FakeSuite
      end
    end

    class FakeRunnableWithoutSuite
      include Inferno::DSL::Messages

      def test_session_id
        "session-1"
      end
    end

    def test_add_message_rewrites_matching_validator_style_message
      runnable = FakeRunnable.new
      runnable.add_message("error", "Patient/123: Patient.name[0].given: Minimum required = 1, but only found 0")

      assert_includes runnable.messages.first[:message], "[Patient.name[0].given](https://fhirpath-lab.com?"
    end

    def test_add_message_leaves_message_untouched_without_session_id
      runnable = FakeRunnable.new(test_session_id: nil)
      original = "Patient/123: Patient.name[0].given: detail"
      runnable.add_message("error", original)

      assert_equal original, runnable.messages.first[:message]
    end

    def test_add_message_leaves_message_untouched_when_suite_lacks_constants
      runnable = FakeRunnableWithoutSuite.new
      original = "Patient/123: Patient.name[0].given: detail"
      runnable.add_message("error", original)

      assert_equal original, runnable.messages.first[:message]
    end
  end
end
