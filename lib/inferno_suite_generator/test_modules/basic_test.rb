# frozen_string_literal: true

require_relative "../decorators/parameters_parameter_decorator"
require_relative "../utils/basic_test_helpers"

module InfernoSuiteGenerator
  # Module provides shared utility methods for FHIR test modules.
  # It supports resource management and cleanup operations including:
  #
  # - Registering resources for teardown after test completion
  # - Maintaining a registry of created resource IDs
  # - Managing scratch space for temporary test data
  # - Providing access to demo data configurations
  module BasicTest
    extend Forwardable
    include BasicTestHelpers

    def_delegators "self.class", :demodata, :metadata

    NOT_FOUND_STATUS = 404
    ATTEMPTS_TO_GET_ENTRIES = 10.freeze

    def resource_payload_for_input
      payload = resource_body_by_resource_type(resource_type).first
      skip skip_message(resource_type) if payload.nil?

      parse_fhir_resource(payload.to_json)
    end

    def available_resource_id
      available_id = existing_demo_resources&.first
      skip "Can't find ID of resource #{resource_type} for UPDATE" if available_id.nil?

      available_id
    end

    def available_resource_id_list
      teardown_ids = teardown_candidates.select { |resource| resource.resourceType == resource_type }.map(&:id)
      available_ids = existing_demo_resources[0..9]
      all_available_ids = teardown_ids + available_ids
      skip "Can't find ID of resource #{resource_type} for UPDATE" if all_available_ids.empty?

      all_available_ids
    end

    def register_teardown_candidate
      return unless resource
      return if formatted_teardown_candidates.include? "#{resource.resourceType}/#{resource.id}"

      info "Registering #{resource.resourceType} with #{resource.id} for teardown"
      teardown_candidates << resource
    end

    def register_resource_id
      return unless resource
      return if existing_demo_resources.include? resource.id

      info "Registering #{resource.id} of #{resource.resourceType} for resource IDs registry"
      demo_resources[resource_type] << resource.id
    end

    def register_resource_id_from_bundle(bundle)
      return unless bundle

      bundle.entry&.map do |entry|
        resource = entry&.resource

        info "Registering #{resource.id} of #{resource.resourceType} for resource IDs registry"
        return if existing_demo_resources.include? resource.id

        existing_demo_resources << resource.id
      end
    end

    def teardown_candidates
      scratch[:teardown_candidates] ||= []
    end

    def demo_resources
      scratch[:resource_ids] ||= demodata.resource_ids
    end

    def resource_body_by_resource_type(resource_type)
      # NOTE: This method should be more complex. We should try to read CapabilityStatement of the server
      # to identify the ability to search resources.
      # 1. Check if there is any supported references for this resource type/profile;
      # 2. If there is any supported references, then we need to check CapabilityStatement to ability to search these references resources;
      # 3. If the search is available, then we need to get references of the available resources on server;
      # 4. Then we need to add references to the resource body for each resource in the list.
      resources_by_resource_type = resource_body_list[resource_type] || []
      if resources_by_resource_type.empty?
        warning "No #{resource_type} resources appear to be available."

        return []
      end

      resource_filtered_by_profile = resources_by_resource_type.select do |resource|
        next false if resource["meta"].blank?
        next false if resource["meta"]["profile"].blank?

        resource["meta"]["profile"].include?(metadata.profile_url)
      end

      if resource_filtered_by_profile.empty?
        warning "No #{resource_type} resources appear to be available with profile #{metadata.profile_url}"

        return resources_by_resource_type
      end

      resource_filtered_by_profile
    end

    def any_profile_matches_with_target_profiles(resource, target_profiles)
      return false if resource.meta.nil?
      return false if resource.meta.profile.nil?

      resource.meta.profile.any? do |profile|
        target_profiles.include?(profile)
      end
    end

    def resource_body_list
      scratch[:resource_body_list] ||= demodata.resource_body_list
    end

    def patch_body_list
      initial_demodata = extra_bundle.nil? ? demodata.patch_body_list : patch_body_list_from_input
      scratch[:patch_body_list] ||= initial_demodata
    end

    def patch_body_list_from_input
      info "The test suite will use the data from the provided bundle to PATCH resources"
      bundle = parse_fhir_resource(extra_bundle)
      patch_entries = bundle.entry.select do |entry|
        request = entry.request
        return false if request.nil?

        request.local_method == "PATCH"
      end
      get_patch_body_list(patch_entries)
    end

    def get_patch_body_list(bundle_patch_entries)
      result = default_patch_body_list

      bundle_patch_entries.each do |entry|
        resource_type = entry.request.url.split("/").first
        result[:FHIRPATHPatchJson][resource_type] << entry.resource.source_hash
        result[:JSONPatch][resource_type] << ParametersParameterDecorator.new(
          entry.resource.parameter.first
        ).patchset_data
      end

      result
    end

    def patch_body_list_by_patch_type(patch_type)
      patch_body_list[patch_type.to_sym] || {}
    end

    def patch_body_list_by_patch_type_and_resource_type(patch_type, resource_type)
      patch_body_list_by_patch_type(patch_type)[resource_type].reverse || []
    end

    def parse_fhir_resource(payload)
      FHIR.from_contents(payload)
    rescue StandardError => e
      skip "Can't create resource from provided data: #{e.message}"
    end

    private

    def formatted_teardown_candidates
      teardown_candidates.map { |resource| "#{resource.resourceType}/#{resource.id}" }
    end

    def existing_demo_resources
      demo_resources[resource_type] ||= []
    end
  end
end
