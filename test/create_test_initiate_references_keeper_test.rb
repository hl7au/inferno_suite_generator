# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"
require "inferno_suite_generator/test_modules/create_test"

module InfernoSuiteGenerator
  class CreateTestInitiateReferencesKeeperTest < Minitest::Test
    # Test double that includes CreateTest and provides dependencies for initiate_references_keeper.
    # Configure search_results: { resource_type => { status: N, bundle: FHIR::Bundle or nil } }
    # so that fhir_search(resource_type) sets response and resource accordingly.
    class TestableCreateTest
      include CreateTest

      attr_reader :metadata, :references_keeper, :demodata
      attr_accessor :search_results, :info_messages

      def initialize(metadata:, references_keeper:, demodata:)
        @metadata = metadata
        @references_keeper = references_keeper
        @demodata = demodata
        @search_results = {}
        @info_messages = []
      end

      def fhir_search(resource_type)
        result = search_results[resource_type]
        return unless result

        @response = { status: result[:status] }
        @resource = result[:bundle]
      end

      def response
        @response || {}
      end

      def resource
        @resource
      end

      def info(message)
        info_messages << message
      end
    end

    def test_returns_early_when_references_keeper_already_has_references
      demodata = demodata_double(["Patient", "Observation"])
      keeper = references_keeper_double("Patient" => ["p1"])
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        references_keeper: keeper,
        demodata: demodata
      )
      subject.search_results = { "Patient" => { status: 200, bundle: build_bundle("Patient", "p1") } }

      subject.send(:initiate_references_keeper)

      assert subject.info_messages.empty?, "should not search when keeper already has references"
      assert_equal 1, keeper.references["Patient"].size
    end

    def test_searches_each_resource_type_and_adds_references_from_bundle
      bundle_patient = build_bundle("Patient", "patient-123")
      demodata = demodata_double(["Patient"])
      keeper = references_keeper_double({})
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        references_keeper: keeper,
        demodata: demodata
      )
      subject.search_results = { "Patient" => { status: 200, bundle: bundle_patient } }

      subject.send(:initiate_references_keeper)

      assert keeper.references.key?("Patient")
      assert_includes keeper.references["Patient"], "patient-123"
    end

    def test_skips_resource_type_when_response_status_is_not_200
      demodata = demodata_double(["Patient"])
      keeper = references_keeper_double({})
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        references_keeper: keeper,
        demodata: demodata
      )
      subject.search_results = { "Patient" => { status: 404, bundle: build_bundle("Patient", "p1") } }

      subject.send(:initiate_references_keeper)

      assert_includes subject.info_messages.first, "Can't search for Patient"
      refute keeper.references.key?("Patient"), "should not add references when status != 200"
    end

    def test_skips_resource_type_when_bundle_is_nil
      demodata = demodata_double(["Patient"])
      keeper = references_keeper_double({})
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        references_keeper: keeper,
        demodata: demodata
      )
      subject.search_results = { "Patient" => { status: 200, bundle: nil } }

      subject.send(:initiate_references_keeper)

      assert_includes subject.info_messages.first, "Can't get bundle for Patient"
      refute keeper.references.key?("Patient")
    end

    def test_skips_resource_type_when_bundle_entry_is_nil
      # Use a mock bundle so entry is truly nil (FHIR::Bundle.new(entry: nil) normalizes to [])
      bundle = Struct.new(:entry).new(nil)
      demodata = demodata_double(["Patient"])
      keeper = references_keeper_double({})
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        references_keeper: keeper,
        demodata: demodata
      )
      subject.search_results = { "Patient" => { status: 200, bundle: bundle } }

      subject.send(:initiate_references_keeper)

      assert_includes subject.info_messages.first, "Bundle entry is nil"
      refute keeper.references.key?("Patient")
    end

    def test_skips_resource_type_when_bundle_entry_is_empty
      bundle = FHIR::Bundle.new(entry: [])
      demodata = demodata_double(["Patient"])
      keeper = references_keeper_double({})
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        references_keeper: keeper,
        demodata: demodata
      )
      subject.search_results = { "Patient" => { status: 200, bundle: bundle } }

      subject.send(:initiate_references_keeper)

      assert_includes subject.info_messages.first, "No Patient resources found"
      refute keeper.references.key?("Patient")
    end

    def test_processes_multiple_resource_types_and_adds_from_each_valid_bundle
      bundle_patient = build_bundle("Patient", "p1")
      bundle_obs = build_bundle("Observation", "obs-1")
      demodata = demodata_double(["Patient", "Observation"])
      keeper = references_keeper_double({})
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        references_keeper: keeper,
        demodata: demodata
      )
      subject.search_results = {
        "Patient" => { status: 200, bundle: bundle_patient },
        "Observation" => { status: 200, bundle: bundle_obs }
      }

      subject.send(:initiate_references_keeper)

      assert_includes keeper.references["Patient"], "p1"
      assert_includes keeper.references["Observation"], "obs-1"
    end

    def test_skips_failed_type_but_processes_successful_types
      bundle_patient = build_bundle("Patient", "p1")
      demodata = demodata_double(["Observation", "Patient"])
      keeper = references_keeper_double({})
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        references_keeper: keeper,
        demodata: demodata
      )
      subject.search_results = {
        "Observation" => { status: 500, bundle: nil },
        "Patient" => { status: 200, bundle: bundle_patient }
      }

      subject.send(:initiate_references_keeper)

      assert_includes subject.info_messages.first, "Can't search for Observation"
      assert keeper.references.key?("Patient")
      assert_includes keeper.references["Patient"], "p1"
    end

    def test_does_nothing_when_resource_types_to_search_is_empty
      demodata = demodata_double([])
      keeper = references_keeper_double({})
      subject = TestableCreateTest.new(
        metadata: metadata_double,
        references_keeper: keeper,
        demodata: demodata
      )

      subject.send(:initiate_references_keeper)

      assert subject.info_messages.empty?
      assert keeper.references.empty?
    end

    private

    def metadata_double
      Struct.new(:references).new([])
    end

    def demodata_double(resource_types_to_search)
      Struct.new(:resource_types_to_search).new(resource_types_to_search)
    end

    def references_keeper_double(initial_refs = {})
      refs = initial_refs.transform_values(&:dup)
      Class.new do
        attr_reader :references

        def initialize(refs)
          @references = refs
        end

        def add_references_from_bundle(bundle)
          refs = bundle.entry.map(&:resource).map { |r| "#{r.resourceType}/#{r.id}" }
          refs.each { |ref| add_reference(ref) }
        end

        def add_reference(reference)
          resource_type, resource_id = reference.split("/", 2)
          @references[resource_type] ||= []
          @references[resource_type] << resource_id
          @references[resource_type].uniq!
        end
      end.new(refs)
    end

    def build_bundle(resource_type, resource_id)
      res = FHIR.from_contents({ resourceType: resource_type, id: resource_id }.to_json)
      entry = FHIR::Bundle::Entry.new(resource: res)
      FHIR::Bundle.new(entry: [entry])
    end
  end
end
