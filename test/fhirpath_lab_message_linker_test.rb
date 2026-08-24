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

    def test_linkify_rewrites_message_with_echoed_resource_type_segment
      message = "Patient/pat-sf: Patient: Patient.extension[0]: Internal validator error occurred: " \
                "Could not find value set https://healthterminologies.gov.au/fhir/ValueSet/foo and version null."

      result = linkify(message)

      expected_link = "[Patient.extension[0]](https://fhirpath-lab.com?" \
                      "expression=Patient.extension%5B0%5D&engine=fhirpath.js&" \
                      "resource=http%3A%2F%2Fkeeper.example%2Fsession-1%2FPatient%2Fpat-sf)"
      assert_equal "Patient/pat-sf: Patient: #{expected_link}: Internal validator error occurred: " \
                   "Could not find value set https://healthterminologies.gov.au/fhir/ValueSet/foo and version null.",
                   result
    end

    def test_linkify_treats_bare_type_as_path_when_no_further_segment_follows
      message = "Patient/123: Patient: Minimum required = 1, but only found 0"

      result = linkify(message)

      expected_link = "[Patient](https://fhirpath-lab.com?" \
                      "expression=Patient&engine=fhirpath.js&" \
                      "resource=http%3A%2F%2Fkeeper.example%2Fsession-1%2FPatient%2F123)"
      assert_equal "Patient/123: #{expected_link}: Minimum required = 1, but only found 0", result
    end

    def test_linkify_leaves_message_untouched_when_base_url_missing
      message = "Patient/123: Patient.name[0].given: detail"
      assert_equal message, linkify(message, base_url: nil)
    end

    def test_linkify_leaves_message_untouched_when_resource_base_url_missing
      message = "Patient/123: Patient.name[0].given: detail"
      assert_equal message, linkify(message, resource_base_url: nil)
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

    def test_linkify_rewrites_only_matching_lines_in_a_multiline_message
      message = "Validation results:\n\n" \
                "Patient/123: Patient.name[0].given: Minimum required = 1, but only found 0\n\n" \
                "Patient/123: Patient.birthDate: is required\n\n" \
                "See the report for details."

      lines = linkify(message).split("\n", -1)

      assert_equal message.split("\n", -1).length, lines.length
      assert_equal ["Validation results:", "", "", "", "See the report for details."],
                   lines.values_at(0, 1, 3, 5, 6)
      assert_includes lines[2], "[Patient.name[0].given](https://fhirpath-lab.com?"
      assert_includes lines[4], "[Patient.birthDate](https://fhirpath-lab.com?"
    end

    def test_linkify_leaves_multiline_message_untouched_when_no_lines_match
      message = "Validation results:\n\nSomething went wrong\n\nSee the report for details."
      assert_equal message, linkify(message)
    end

    def test_linkify_returns_non_string_untouched
      assert_nil linkify(nil)
    end

    def test_linkify_handles_a_colon_embedded_in_the_path
      path = "Patient.identifier.where(system='http://hl7.org.au/id/medicare-number').value"
      message = "Patient/123: #{path}: code is invalid"

      result = linkify(message)

      expected_link = "[#{path}](https://fhirpath-lab.com?" \
                      "expression=#{CGI.escape(path)}" \
                      "&engine=fhirpath.js&resource=http%3A%2F%2Fkeeper.example%2Fsession-1%2FPatient%2F123)"
      assert_equal "Patient/123: #{expected_link}: code is invalid", result
    end

    private

    def linkify(message, base_url: "https://fhirpath-lab.com/", resource_base_url: "http://keeper.example",
                session_id: "session-1")
      FhirpathLabMessageLinker.linkify(message, base_url:, resource_base_url:, session_id:)
    end
  end

  class MessagesFhirpathLabPatchTest < Minitest::Test
    # `resource_base_url_for_message_linker` reads `Inferno::Application['base_url']`,
    # which is only defined once the full inferno_core gem boots (it requires a host
    # app's `config/database.yml`). This gem's own tests don't boot inferno_core, so
    # `test_helper` stands in a minimal fake `Inferno::Application` rather than
    # pulling that in.
    class FakeSuite
      FHIRPATHLAB_URL = "https://fhirpath-lab.com/"

      def self.id
        :fake_suite
      end
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

      message = runnable.messages.first[:message]
      assert_includes message, "[Patient.name[0].given](https://fhirpath-lab.com?"
      assert_includes message,
                      CGI.escape("http://localhost:4567/custom/fake_suite/resources/session-1/Patient/123")
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

    def test_add_message_leaves_message_untouched_when_base_url_lookup_raises_dry_container_error
      runnable = FakeRunnable.new
      original = "Patient/123: Patient.name[0].given: detail"

      Inferno::Application.stub(:[], ->(_key) { raise Dry::Container::Error, "Nothing registered with the key" }) do
        runnable.add_message("error", original)
      end

      assert_equal original, runnable.messages.first[:message]
    end
  end
end
