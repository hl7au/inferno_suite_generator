# frozen_string_literal: true

require_relative "basic_test"
require_relative "../utils/set_by_path"
require_relative "../utils/create_test_helpers"
require_relative "../utils/dynamic_value_resolver"
require_relative "../decorators/capability_statement_decorator"
require_relative "../decorators/fhir_search_response"
require "json"

module InfernoSuiteGenerator
  # Module handles sending FHIR resource instances
  # to a server via the create operation and validating the response. It supports:
  #
  # - Converting input data into FHIR resource instances
  # - Sending create requests to FHIR servers
  # - Validating response status codes and resource types
  # - Verifying server-assigned resource IDs
  module CreateTest
    include BasicTest
    include SetByPath
    include CreateTestHelpers
    include DynamicValueResolver

    EXPECTED_CREATE_STATUS = 201

    def perform_create_test
      resource = prepare_resource_for_create
      send_create_and_register(resource)
    end

    private

    def prepare_resource_for_create
      initiate_references_keeper
      resource = update_resource_by_references(resource_payload_for_input)
      apply_create_overrides(resource)
    end

    def apply_create_overrides(resource)
      return resource if create_resource_overrides.empty?

      resource_data = resource.to_hash
      create_resource_overrides.each do |path, value|
        resource_data = SetByPath.set_by_path(resource_data, path, resolve_dynamic_values(value))
      end
      FHIR.from_contents(resource_data.to_json)
    end

    def send_create_and_register(resource)
      fhir_create(resource)
      assert_create_success
      ensure_id_present(resource_type)
      register_teardown_candidate
      register_resource_id
    end

    def initiate_references_keeper
      return if references_keeper.references.keys.any?

      add_references_from_server
      references_keeper.add_references_from_input(references_mapping_input) if references_mapping_input.present?
    end

    def add_references_from_server
      filtered_demodata.each do |resource_type|
        bundle = fetch_valid_bundle_for_resource_type(resource_type)
        references_keeper.add_references_from_bundle(bundle) if bundle
      end
    end

    def filtered_demodata
      resources_to_search = resources_available_for_search
      demodata.resource_types_to_search.select do |resource_type|
        resources_to_search.include?(resource_type)
      end
    end

    def resources_available_for_search
      fhir_get_capability_statement
      CapabilityStatementDecorator.new(resource).get_resources_by_interaction("search-type")&.map(&:type)&.uniq
    end

    def fetch_valid_bundle_for_resource_type(resource_type)
      bundle = search_bundle_for_resource_type(resource_type)
      return nil unless valid_bundle_for_references?(bundle, resource_type)

      bundle
    end

    def search_bundle_for_resource_type(resource_type)
      fhir_request = fhir_search(resource_type)
      delete_last_request
      FHIRSearchResponse.new(fhir_request).to_bundle
    end

    def requests_collection
      requests || []
    end

    def delete_last_request
      requests_collection.delete_at(-1)
    end

    def valid_bundle_for_references?(bundle, resource_type)
      return skip_log?("Can't get bundle for #{resource_type} resources. Skipping this resource type...") unless bundle

      entries = bundle.entry
      return skip_log?("Bundle entry is nil. Skipping this resource type...") unless entries
      return skip_log?("No #{resource_type} resources found. Skipping this resource type...") if entries.empty?

      true
    end

    def skip_log?(message)
      info message
      false
    end

    def assert_create_success
      assert_response_status(EXPECTED_CREATE_STATUS)
      assert_resource_type(resource_type)
    end

    def ensure_id_present(type)
      assert resource.id.present?, missing_id_message(type)
    end

    def skip_message(resource_type)
      "No #{resource_type} resource provided for create test"
    end

    def missing_id_message(resource_type)
      "Expected server to return an id for created #{resource_type}."
    end
  end
end
