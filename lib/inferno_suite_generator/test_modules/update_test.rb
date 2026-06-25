# frozen_string_literal: true

require_relative "basic_test"
require_relative "../utils/set_by_path"
require_relative "../utils/create_test_helpers"
require_relative "../utils/reference_initializer"
require "securerandom"

module InfernoSuiteGenerator
  # Module handles sending FHIR resource instances
  # to a server via the update operation and validating the response. It supports:
  #
  # - Retrieving existing FHIR resource instances for update
  # - Sending update requests to FHIR servers
  # - Validating response status codes (200, 201, 204)
  # - Handling update operation success scenarios
  module UpdateTest
    include BasicTest
    include SetByPath
    include CreateTest::CreateTestHelpers
    include ReferenceInitializer

    EXPECTED_UPDATE_STATUS = 200
    EXPECTED_UPDATE_NEW_STATUS = 201
    EXPECTED_UPDATE_STATUS_WITH_NO_CONTENT = 204

    def perform_update_test
      current_resource_id = nil
      current_resource_version = nil
      is_success_test = false
      normalized_data.each do |data|
        resource_id = data[:resource_id]
        resource_payload = data[:resource_payload]
        attempt = data[:attempt]

        fhir_update(resource_payload, resource_id)
        response_resource_version = resource&.meta&.versionId
        response_status = response[:status]

        status_okay = response_status == EXPECTED_UPDATE_STATUS
        version_okay = !response_resource_version.nil? &&
                       !current_resource_version.nil? &&
                       (response_resource_version.to_i > current_resource_version.to_i)
        attempt_okay = attempt > 1
        resource_id_is_okay = resource_id == current_resource_id

        if [status_okay, version_okay, attempt_okay, resource_id_is_okay].all?
          is_success_test = true
          break
        else
          current_resource_id = resource_id
          current_resource_version = response_resource_version.to_i
        end
      end

      assert is_success_test, "Resource version was not updated or status was not #{EXPECTED_UPDATE_STATUS}."
    end

    def perform_update_new_test
      resource_to_update = prepare_resource_for_update_new
      resource_id = SecureRandom.uuid
      resource_to_update.id = resource_id
      fhir_update(resource_to_update, resource_id)
      assert_update_new_success
      register_teardown_candidate
      register_resource_id
    end

    private

    def prepare_resource_for_update_new
      initiate_references_keeper
      update_resource_by_references(resource_payload_for_input)
    end

    def normalized_data
      initiate_references_keeper
      result = []
      available_resource_id_list.uniq.each do |resource_id|
        idx = 0
        resource_payload_arr_for_input.each do |resource|
          resolved = update_resource_by_references(resource)
          resolved.id = resource_id
          result << prepare_normalized_data_item(resource_id, resolved, idx)
          idx += 1
        end
      end
      result
    end

    def prepare_normalized_data_item(resource_id, resource, index)
      {
        resource_id: resource_id,
        resource_payload: resource,
        attempt: index + 1
      }
    end

    def resource_payload_arr_for_input
      payload = resource_body_by_resource_type(resource_type)
      skip skip_message(resource_type) if payload.blank?

      payload.map { |item| parse_fhir_resource(item.to_json) }
    end

    def assert_update_success
      response_status = response[:status]
      assert [EXPECTED_UPDATE_STATUS,
              EXPECTED_UPDATE_STATUS_WITH_NO_CONTENT].include?(response_status),
             error_message(response_status)
    end

    def assert_update_new_success
      response_status = response[:status]
      assert response_status == EXPECTED_UPDATE_NEW_STATUS,
             error_message(response_status)
    end

    def skip_message(resource_type)
      "No #{resource_type} resource provided for update test"
    end

    def error_message(response_status)
      "Response status is #{response_status}. Expected #{EXPECTED_UPDATE_NEW_STATUS}, #{EXPECTED_UPDATE_STATUS} or
              #{EXPECTED_UPDATE_STATUS_WITH_NO_CONTENT}"
    end
  end
end
