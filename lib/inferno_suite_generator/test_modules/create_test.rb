# frozen_string_literal: true

require_relative "basic_test"
require_relative "../utils/set_by_path"
require_relative "../utils/create_test_helpers"
require_relative "../utils/dynamic_value_resolver"
require_relative "../utils/reference_initializer"
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
    include ReferenceInitializer

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
