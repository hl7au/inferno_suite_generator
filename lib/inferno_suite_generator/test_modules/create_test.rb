# frozen_string_literal: true

require_relative "basic_test"
require_relative "../utils/set_by_path"

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

    EXPECTED_CREATE_STATUS = 201

    def perform_create_test
      initiate_references_keeper
      info "Default resource payload: #{resource_payload_for_input.to_json}"
      resource = update_resource_by_references(resource_payload_for_input)
      info "Resource with references: #{resource.to_json}"
      fhir_create(resource_payload_for_input)
      assert_create_success
      ensure_id_present(resource_type)
      register_teardown_candidate
      register_resource_id
    end

    private

    def update_resource_by_references(resource)
      resource_data = deep_copy_hash(resource.to_hash)
      references_ig_config = metadata.references
      paths_to_set = references_ig_config.map { |reference_metadata| reference_metadata[:path] }.uniq
      paths_and_values_to_set = paths_to_set.map do |path|
        current_reference = references_ig_config.find { |reference_metadata| reference_metadata[:path] == path }
        next if current_reference.nil?
        next if current_reference[:resource_types].empty?

        resource_id = references_keeper.references_for_resource_type(current_reference[:resource_types].first).first
        next if resource_id.nil?

        [path, { "reference" => "#{current_reference[:resource_types].first}/#{resource_id}" }]
      end
      resource_data = SetByPath.multi_set_by_path(resource_data, paths_and_values_to_set.compact)
      info "References keeper: #{references_keeper.inspect}"
      info "Resource data with references (JSON): #{resource_data.to_json}"
      FHIR.from_contents(resource_data.to_json)
    end

    def initiate_references_keeper
      references_ig_config = metadata.references
      references_ig_config.each do |reference_metadata|
        references_keeper.add_references(
          reference_metadata[:resource_types].map do |resource_type|
            fhir_search(resource_type)
            if response[:status] != 200
              info "Can't search for #{resource_type} resources. Skipping this resource type..."
              next
            end
            bundle = resource
            if bundle.nil?
              info "Can't get bundle for #{resource_type} resources. Skipping this resource type..."
              next
            end
            if bundle.entry.nil?
              info "Bundle entry is nil. Skipping this resource type..."
              next
            end
            if bundle.entry.empty?
              info "No #{resource_type} resources found. Skipping this resource type..."
              next
            end
            bundle_resources = bundle.entry.map(&:resource)
            bundle_resources.select do |resource|
              any_profile_matches_with_target_profiles(resource, reference_metadata[:profiles])
            end.map { |resource| "#{resource.resourceType}/#{resource.id}" }
          end.flatten.compact
        )
      end
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
