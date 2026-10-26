# frozen_string_literal: true

require "minitest/autorun"
require "fhir_models"
require "inferno/dsl/assertions"
require "inferno/dsl/messages"
require "inferno/dsl/results"
require "inferno/exceptions"
require_relative "../runtime/profile_read_test"

module InfernoSuitePlugins
  module ProfileRead
    # Runs the runtime module the way Inferno does, with Inferno's own assertions, skips and messages, against
    # a stubbed FHIR server. Each id in server maps to the status and the resource a read of it returns.
    class RuntimeTest < Minitest::Test
      PROFILE_URL = "http://example.org/StructureDefinition/example-patient"

      # A generated test: plugin_metadata comes from the class, the FHIR client and the validator are stubbed.
      class FakeReadTest
        include Inferno::DSL::Assertions
        include Inferno::DSL::Messages
        include Inferno::DSL::Results
        include ProfileReadTest

        class << self
          attr_accessor :plugin_metadata
        end

        attr_reader :messages, :reads, :validations, :response, :resource

        def initialize(server, invalid_ids: [])
          @server = server
          @invalid_ids = invalid_ids
          @messages = []
          @reads = []
          @validations = []
        end

        def fhir_read(resource_type, id)
          @reads << [resource_type, id]
          status, @resource = @server.fetch(id, [404, nil])
          @response = { status: }
        end

        def resource_is_valid?(profile_url:, message_prefix:)
          @validations << [profile_url, message_prefix]
          !@invalid_ids.include?(resource.id)
        end
      end

      def setup
        FakeReadTest.plugin_metadata = { "resource_type" => "Patient", "profile_url" => PROFILE_URL,
                                         "profile_version" => "1.0.0", "validate" => true }
      end

      def test_every_id_is_read_and_validated
        test = run_test("pat-1, pat-2", { "pat-1" => ok(patient("pat-1")), "pat-2" => ok(patient("pat-2")) })

        assert_equal [%w[Patient pat-1], %w[Patient pat-2]], test.reads
        assert_equal [["#{PROFILE_URL}|1.0.0", "Patient/pat-1: "], ["#{PROFILE_URL}|1.0.0", "Patient/pat-2: "]],
                     test.validations
        assert_empty test.messages
      end

      def test_ids_are_split_on_commas_and_whitespace_and_deduplicated
        test = run_test(" pat-1,pat-2\npat-1 ,", { "pat-1" => ok(patient("pat-1")), "pat-2" => ok(patient("pat-2")) })

        assert_equal(%w[pat-1 pat-2], test.reads.map(&:last))
      end

      def test_no_ids_skips
        error = assert_raises(Inferno::Exceptions::SkipException) { run_test(" , ", {}) }

        assert_includes error.message, "No Patient ids to read"
      end

      def test_every_failing_id_is_listed
        server = { "pat-1" => ok(patient("pat-1")), "wrong" => ok(patient("other")),
                   "obs" => ok(FHIR::Observation.new(id: "obs")) }

        error = assert_raises(Inferno::Exceptions::AssertionException) do
          run_test("missing, pat-1, wrong, obs", server)
        end

        assert_equal "3 of 4 Patient reads failed:\n\n" \
                     "- missing: expected HTTP 200, got 404\n" \
                     "- wrong: the server returned id \"other\"\n" \
                     "- obs: expected a Patient, got Observation",
                     error.message
      end

      def test_a_resource_that_fails_validation_fails
        error = assert_raises(Inferno::Exceptions::AssertionException) do
          run_test("pat-1", { "pat-1" => ok(patient("pat-1")) }, invalid_ids: ["pat-1"])
        end

        assert_includes error.message, "- pat-1: doesn't conform to #{PROFILE_URL}|1.0.0"
      end

      def test_validate_false_skips_validation
        FakeReadTest.plugin_metadata["validate"] = false

        test = run_test("pat-1", { "pat-1" => ok(patient("pat-1")) }, invalid_ids: ["pat-1"])

        assert_empty test.validations
      end

      def test_without_a_profile_version_the_bare_url_is_validated
        FakeReadTest.plugin_metadata["profile_version"] = nil

        test = run_test("pat-1", { "pat-1" => ok(patient("pat-1")) })

        assert_equal [[PROFILE_URL, "Patient/pat-1: "]], test.validations
      end

      def test_a_resource_that_does_not_claim_the_profile_gets_a_warning
        test = run_test("bare", { "bare" => ok(FHIR::Patient.new(id: "bare")) })

        assert_equal [{ type: "warning", message: "Patient/bare doesn't list #{PROFILE_URL} in meta.profile." }],
                     test.messages
      end

      private

      def run_test(ids, server, invalid_ids: [])
        FakeReadTest.new(server, invalid_ids:).tap { |test| test.run_profile_read_test(ids) }
      end

      def ok(resource)
        [200, resource]
      end

      def patient(id)
        FHIR::Patient.new(id:, meta: { profile: ["#{PROFILE_URL}|1.0.0"] })
      end
    end
  end
end
