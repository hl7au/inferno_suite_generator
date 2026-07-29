# frozen_string_literal: true

require_relative "../patch_checks"
require_relative "../utils/generic"
require_relative "basic_test"

module InfernoSuiteGenerator
  # Module handles sending FHIR resource instances
  # to a server via the patch operation and validating the response. It supports:
  #
  # - Retrieving existing FHIR resource instances for patching
  # - Sending patch requests to FHIR servers
  # - Validating response status codes (200, 204)
  # - Handling patch operation success scenarios
  module PatchTest
    include GenericUtils
    include BasicTest

    SUCCESS = 200
    SUCCESS_NO_CONTENT = 204

    CONTENT_TYPE_HEADERS = {
      "JSONPatch" => "application/json-patch+json",
      "XMLPatch" => "application/xml-patch+xml",
      "FHIRPathPatchJSON" => "application/fhir+json",
      "FHIRPathPatchXML" => "application/fhir+xml"
    }.freeze

    # Overridden by generated tests when `configs.generic.patch_checks` narrows the default set.
    def patch_checks
      PATCH_CHECKS
    end

    def perform_json_patch_test
      patchset = patch_body_list_by_patch_type_and_resource_type("JSONPatch", resource_type)
      skip skip_message(resource_type) if patchset.nil?

      available_resource_id_list.each do |resource_id|
        fhir_patch(resource_type, resource_id, patchset)
        break unless response[:status] == NOT_FOUND_STATUS

        info "Resource with id #{resource_id} not found. Waiting other ID..."
        next
      end
      assert_patch_success(patchset)
    end

    def perform_xml_patch_test
      # TODO: TBI
      skip "Not implemented"
    end

    def perform_fhirpath_patch_json_test
      patchsets = patch_body_list_by_patch_type_and_resource_type("FHIRPATHPatchJson", resource_type)
      skip skip_message(resource_type) if patchsets.nil? || patchsets.empty?

      parameters_resource_hash_list = patchsets[0..9]
      is_success_test = false
      normalized_data = []

      available_resource_id_list.uniq.each do |resource_id|
        idx = 0
        parameters_resource_hash_list&.each do |parameters_resource_hash|
          normalized_data << {
            resource_id: resource_id,
            parameters_resource_hash: parameters_resource_hash,
            attempt: idx + 1
          }
          idx += 1
        end
      end

      current_resource_id = nil
      current_resource_version = nil
      normalized_data.each do |data|
        resource_id = data[:resource_id]
        parameters_resource_hash = data[:parameters_resource_hash]
        attempt = data[:attempt]

        fhir_fhirpath_patch_json(resource_type, resource_id, parameters_resource_hash)
        response_resource_version = resource&.meta&.versionId
        response_status = response[:status]

        status_okay = response_status == SUCCESS
        version_okay = !response_resource_version.nil? && !current_resource_version.nil? && (response_resource_version.to_i > current_resource_version.to_i)
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

      assert is_success_test, "Resource version was not updated or status was not #{SUCCESS}."
    end

    def perform_fhirpath_patch_xml_text
      # TODO: TBI
      skip "Not implemented"
    end

    private

    def create_interaction_exists?(metadata)
      metadata.interactions.any? do |interaction|
        interaction[:code] == "create" && interaction[:expectation] == "SHALL"
      end
    end

    def resource_ids_fn(resource_type)
      "#{camel_to_snake(resource_type)}_ids"
    end

    def resource_ids_exists?(resource_type)
      respond_to?(resource_ids_fn(resource_type))
    end

    def fetch_resource_ids(resource_type)
      send(resource_ids_fn(resource_type))
    end

    def resource_payload_for_input
      payload = patch_data
      skip skip_message(resource_type) if payload.empty?
      payload
    end

    def assert_patch_success(patchset = nil)
      checks = enabled_patch_checks

      assert_patch_status if checks.include?("status")
      assert_patch_version if checks.include?("version")
      assert_patch_diff(patchset) if checks.include?("diff")
    end

    def enabled_patch_checks
      Array(patch_checks) & PATCH_CHECKS
    end

    def assert_patch_status
      response_status = response[:status]
      status_okay = [SUCCESS, SUCCESS_NO_CONTENT].include?(response_status)

      assert status_okay, error_message_status(response_status)
    end

    def assert_patch_version
      # NOTE: We can only assert on the version when the CREATE interaction is present in the IG
      # for the current profile, since that is what guarantees the resource started at version 1.
      # Resource versioning is not itself a conformance requirement, so this check is skipped
      # (rather than failed) when that guarantee doesn't hold.
      return unless create_interaction_exists?(metadata)

      resource_version = resource&.meta&.versionId
      version_okay = resource_version == "2"

      assert version_okay, error_message_version(resource_version)
    end

    def assert_patch_diff(patchset)
      return if patchset.blank?

      resource_hash = resource&.to_hash
      diff_ok = resource_hash.is_a?(Hash) &&
                patchset.all? { |patch_operation| patch_operation_applied?(resource_hash, patch_operation) }

      assert diff_ok, error_message_diff
    end

    def patch_operation_applied?(resource_hash, patch_operation)
      actual_value = resource_hash[patch_operation[:path].to_s.delete_prefix("/")]

      case patch_operation[:op]
      when "add", "replace"
        actual_value == patch_operation[:value]
      when "remove"
        actual_value.nil?
      else
        true
      end
    end

    def skip_message(resource_type)
      "No #{resource_type} data provided for patch test"
    end

    def error_message_status(response_status)
      "Response status is #{response_status}. Expected #{SUCCESS} or #{SUCCESS_NO_CONTENT}"
    end

    def error_message_version(resource_version)
      "Resource version is #{resource_version}. Expected 2"
    end

    def error_message_diff
      "Resource does not reflect the applied patch"
    end

    def fhir_fhirpath_patch_json(resource_type, id, parameters_resource_hash, client: :default, name: nil, tags: [])
      store_request_and_refresh_token(fhir_client(client), name, tags) do
        tcp_exception_handler do
          headers = fhir_client(client).fhir_headers
          headers["Content-Type"] = CONTENT_TYPE_HEADERS["FHIRPathPatchJSON"]
          headers["Accept"] = CONTENT_TYPE_HEADERS["FHIRPathPatchJSON"]
          body = parameters_resource_hash.to_json

          fhir_client(client).partial_update(fhir_class_from_resource_type(resource_type), id, body)
        end
      end
    end
  end
end
