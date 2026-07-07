# frozen_string_literal: true

require_relative "test_helper"
require "jsonpath"
require "inferno_suite_generator"
require "inferno_suite_generator/test_modules/update_test"

module InfernoSuiteGenerator
  # Reusable reference keeper double shared across UpdateNew test cases.
  KeeperDouble = Class.new do
    attr_reader :references

    def initialize(refs)
      @references = refs
    end

    def references_for_resource_type(resource_type)
      (@references[resource_type] || []).reverse
    end

    def add_references_from_bundle(bundle)
      bundle.entry.map(&:resource).each { |resource| add_reference("#{resource.resourceType}/#{resource.id}") }
    end

    def add_references_from_input(input)
      JSON.parse(input).each { |ref| add_reference(ref) }
    end

    def add_reference(reference)
      resource_type, resource_id = reference.split("/", 2)
      references_for_type = (@references[resource_type] ||= [])
      references_for_type << resource_id
      references_for_type.uniq!
    end
  end

  # Test double that includes UpdateTest and stubs all Inferno runtime dependencies.
  # Captures the resource passed to fhir_update so tests can assert on it.
  class TestableUpdateNewTest
    include UpdateTest

    attr_reader :metadata, :references_keeper, :demodata, :requests,
                :resource, :last_updated_resource
    attr_accessor :references_mapping_input, :info_messages, :search_results

    def initialize(metadata:, references_keeper:, demodata:, resource_payload:)
      @metadata = metadata
      @references_keeper = references_keeper
      @demodata = demodata
      @resource_payload = resource_payload
      @requests = []
      @info_messages = []
      @search_results = {}
      @references_mapping_input = nil
    end

    def resource_type = @resource_payload.resourceType
    def resource_payload_for_input = @resource_payload
    def resource_to_create_filter = nil
    def url = "http://example.com"
    def response = @response || {}
    def register_teardown_candidate; end
    def register_resource_id; end

    def fhir_update(resource, _id)
      @last_updated_resource = resource
      @resource = resource
      @response = { status: 201 }
    end

    def fhir_get_capability_statement
      @resource = build_capability_statement_for_types(search_results.keys)
    end

    def fhir_search(resource_type)
      result = search_results[resource_type]
      return unless result

      status = result[:status]
      bundle = result[:bundle]
      @response = { status: }
      @resource = bundle
      response_body = bundle&.to_json
      @requests << { status:, response_body: }
      Struct.new(:status, :response_body).new(status, response_body)
    end

    def info(message) = info_messages << message
    def skip(message) = raise(Minitest::Skip, message)

    def assert(condition, message = nil)
      raise Minitest::Assertion, message unless condition
    end

    def evaluate_fhirpath(resource:, path:)
      resource_hash = resource.to_hash
      matches = JsonPath.new("$.#{path}").on(resource_hash)
      return matches if matches.present?

      settable?(resource_hash, path) ? [true] : []
    end

    private

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

    def build_capability_statement_for_types(types)
      rest = FHIR::R4::CapabilityStatement::Rest.new
      rest.resource = Array(types).map { |rt| capability_resource(rt) }
      FHIR::R4::CapabilityStatement.new(rest: [rest])
    end

    def capability_resource(resource_type)
      capability = FHIR::R4::CapabilityStatement::Rest::Resource.new
      capability.type = resource_type
      capability.interaction =
        [FHIR::R4::CapabilityStatement::Rest::Resource::Interaction.new("code" => "search-type")]
      capability
    end
  end

  class UpdateTestPerformUpdateNewTest < Minitest::Test
    def test_replaces_subject_encounter_and_author_references
      qr = build_questionnaire_response(subject: { "reference" => "Patient/old" },
                                        encounter: { "reference" => "Encounter/old" },
                                        author: { "reference" => "Practitioner/old" })
      subject = build_subject(metadata: all_three_refs_metadata,
                              keeper: all_three_refs_keeper, resource_payload: qr)
      subject.perform_update_new_test
      updated = subject.last_updated_resource
      assert_equal "Patient/p1", updated.subject.reference
      assert_equal "Encounter/e1", updated.encounter.reference
      assert_equal "Practitioner/pr1", updated.author.reference
    end

    def test_leaves_resource_unchanged_when_no_references_configured
      resource = build_questionnaire_response(subject: { "reference" => "Patient/original" })
      subject = build_subject(metadata: metadata_double(references: []),
                              keeper: references_keeper_double({}),
                              resource_payload: resource)
      subject.perform_update_new_test
      assert_equal "Patient/original", subject.last_updated_resource.subject.reference
    end

    def test_does_not_mutate_original_resource
      resource = build_questionnaire_response(subject: { "reference" => "Patient/original" })
      subject = build_subject(
        metadata: metadata_double(references: [{ path: "subject", resource_types: ["Patient"] }]),
        keeper: references_keeper_double("Patient" => ["new-patient"]),
        resource_payload: resource
      )
      subject.perform_update_new_test
      assert_equal "Patient/original", resource.subject.reference, "original resource must not be mutated"
    end

    def test_assigns_a_new_uuid_as_resource_id
      subject = build_subject(metadata: metadata_double(references: []),
                              keeper: references_keeper_double({}),
                              resource_payload: build_questionnaire_response)
      subject.perform_update_new_test
      refute_nil(updated_id = subject.last_updated_resource.id)
      refute_equal "original-id", updated_id
    end

    def test_uses_references_from_mapping_input_when_keeper_is_empty
      resource = build_questionnaire_response(subject: { "reference" => "Patient/old" })
      subject = build_subject(
        metadata: metadata_double(references: [{ path: "subject", resource_types: ["Patient"] }]),
        keeper: references_keeper_double({}),
        resource_payload: resource
      )
      subject.references_mapping_input = '["Patient/from-input"]'
      subject.perform_update_new_test
      assert_equal "Patient/from-input", subject.last_updated_resource.subject.reference
    end

    def test_populates_references_from_server_bundle
      bundle = build_bundle("Patient", "server-patient")
      subject = build_subject_with_patient_ref(demodata: demodata_double(["Patient"]))
      subject.search_results = { "Patient" => { status: 200, bundle: } }
      subject.perform_update_new_test
      assert_equal "Patient/server-patient", subject.last_updated_resource.subject.reference
    end

    def test_skips_server_search_when_keeper_already_has_references
      bundle = build_bundle("Patient", "from-server")
      subject = build_subject_with_patient_ref(
        keeper: references_keeper_double("Patient" => ["pre-loaded"]),
        demodata: demodata_double(["Patient"])
      )
      subject.search_results = { "Patient" => { status: 200, bundle: } }
      subject.perform_update_new_test
      assert_equal "Patient/pre-loaded", subject.last_updated_resource.subject.reference
      assert subject.info_messages.empty?, "should not search server when keeper already has references"
    end

    private

    def build_subject(metadata:, keeper:, resource_payload:, demodata: demodata_double([]))
      TestableUpdateNewTest.new(metadata:, references_keeper: keeper, demodata:, resource_payload:)
    end

    def build_subject_with_patient_ref(keeper: references_keeper_double({}), demodata: demodata_double([]))
      resource = build_questionnaire_response(subject: { "reference" => "Patient/old" })
      metadata = metadata_double(references: [{ path: "subject", resource_types: ["Patient"] }])
      build_subject(metadata:, keeper:, resource_payload: resource, demodata:)
    end

    def all_three_refs_metadata
      metadata_double(references: [{ path: "subject", resource_types: ["Patient"] },
                                   { path: "encounter", resource_types: ["Encounter"] },
                                   { path: "author", resource_types: ["Practitioner"] }])
    end

    def all_three_refs_keeper
      references_keeper_double("Patient" => ["p1"], "Encounter" => ["e1"], "Practitioner" => ["pr1"])
    end

    def build_questionnaire_response(subject: nil, encounter: nil, author: nil)
      data = { "resourceType" => "QuestionnaireResponse", "id" => "original-id", "status" => "completed" }
      data["subject"] = subject if subject
      data["encounter"] = encounter if encounter
      data["author"] = author if author
      FHIR.from_contents(data.to_json)
    end

    def build_bundle(resource_type, resource_id)
      res = FHIR.from_contents({ resourceType: resource_type, id: resource_id }.to_json)
      FHIR::Bundle.new(entry: [FHIR::Bundle::Entry.new(resource: res)])
    end

    def metadata_double(references:) = Struct.new(:references).new(references)
    def demodata_double(types) = Struct.new(:resource_types_to_search).new(types)

    def references_keeper_double(initial_refs = {})
      KeeperDouble.new(initial_refs.transform_values(&:dup))
    end
  end
end
