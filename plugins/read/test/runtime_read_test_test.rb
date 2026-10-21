# frozen_string_literal: true

require "minitest/autorun"
require "inferno_suite_generator"
require_relative "../runtime/read_test"

module InfernoSuitePlugins
  module Read
    # Runs the runtime module against a stand-in for an Inferno test that answers every read with the
    # requested Patient.
    class RuntimeReadTestTest < Minitest::Test
      class Skipped < StandardError; end

      # The parts of Inferno::Test and BasicTest the module calls.
      class FakeTest
        include ReadTest

        attr_reader :reads, :resource, :kept, :scratch_resources
        attr_accessor :patient_ids

        def initialize
          @reads = []
          @kept = []
          @scratch_resources = {}
        end

        def resource_type = "Patient"
        def assert_response_status(_status); end
        def assert_resource_type(_type); end
        def register_resource_id; end
        def keep_resource(resource) = kept << resource
        def assert(condition, message) = (raise Minitest::Assertion, message unless condition)
        def skip(message) = raise(Skipped, message)

        def fhir_read(_type, id)
          reads << id
          @resource = FHIR::Patient.new(id:)
        end
      end

      def setup
        @test = FakeTest.new
      end

      def test_reads_resources_from_earlier_tests_once_each
        @test.perform_read_test([FHIR::Patient.new(id: "a"), FHIR::Reference.new(reference: "Patient/b"),
                                 FHIR::Patient.new(id: "a"), FHIR::Observation.new(id: "o")])

        assert_equal %w[a b], @test.reads
        assert_equal %w[a b], @test.all_scratch_resources.map(&:id)
        assert_equal %w[a b], @test.kept.map(&:id)
      end

      def test_reads_ids_from_the_ids_input_when_no_earlier_resources
        @test.patient_ids = "x, y"

        @test.perform_read_test(nil)

        assert_equal %w[x y], @test.reads
      end

      def test_skips_without_earlier_resources_or_ids
        assert_raises(Skipped) { @test.perform_read_test([]) }
      end

      def test_fails_when_server_returns_another_id
        @test.define_singleton_method(:fhir_read) { |_type, _id| @resource = FHIR::Patient.new(id: "other") }

        error = assert_raises(Minitest::Assertion) { @test.perform_read_test([FHIR::Patient.new(id: "a")]) }

        assert_match 'Expected resource to have id: `"a"`, but found `"other"`', error.message
      end
    end
  end
end
