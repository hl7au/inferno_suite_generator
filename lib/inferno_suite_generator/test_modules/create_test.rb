# frozen_string_literal: true

require_relative "basic_test"
require_relative "../utils/set_by_path"
require_relative "../decorators/capability_statement_decorator"

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
      resource = prepare_resource_for_create
      send_create_and_register(resource)
    end

    private

    def prepare_resource_for_create
      initiate_references_keeper
      update_resource_by_references(resource_payload_for_input)
    end

    def send_create_and_register(resource)
      fhir_create(resource)
      assert_create_success
      ensure_id_present(resource_type)
      register_teardown_candidate
      register_resource_id
    end

    def update_resource_by_references(resource)
      resource_data = deep_copy_hash(resource.to_hash)
      paths_and_values = build_reference_paths_and_values(metadata.references)
      resource_data = SetByPath.multi_set_by_path(resource_data, paths_and_values)
      FHIR.from_contents(resource_data.to_json)
    end

    def build_reference_paths_and_values(references_ig_config)
      paths_to_set = references_ig_config.map { |ref| ref[:path] }.uniq
      paths_to_set.filter_map { |path| reference_pair_for_path(path, references_ig_config) }
    end

    def reference_pair_for_path(path, references_ig_config)
      current_reference = references_ig_config.find { |ref| ref[:path] == path }
      return unless current_reference && current_reference[:resource_types]&.any?

      pair_from_reference(current_reference, path)
    end

    def pair_from_reference(ref, path)
      resource_type = ref[:resource_types].first
      resource_id = references_keeper.references_for_resource_type(resource_type).first
      return unless resource_id

      [path, { "reference" => "#{resource_type}/#{resource_id}" }]
    end

    def initiate_references_keeper
      return if references_keeper.references.keys.any?
      add_references_from_server
      references_keeper.add_references_from_input(references_mapping_input) if references_mapping_input.present?
    end

    def add_references_from_server
      filtered_demodata = demodata.resource_types_to_search.select { |resource_type| resources_available_for_search.include?(resource_type) }
      filtered_demodata.each do |resource_type|
        bundle = fetch_valid_bundle_for_resource_type(resource_type)
        references_keeper.add_references_from_bundle(bundle) if bundle
      end
    end

    def resources_available_for_search
      fhir_get_capability_statement
      cs_resource = CapabilityStatementDecorator.new(resource)
      cs_resource.get_resources_by_interaction("search-type")&.map(&:type)&.uniq
    end

    def fetch_valid_bundle_for_resource_type(resource_type)
      bundle = search_bundle_for_resource_type(resource_type)
      return nil unless valid_bundle_for_references?(bundle, resource_type)

      bundle
    end

    def search_bundle_for_resource_type(resource_type)
      fhir_search(resource_type)
      unless search_successful?
        info "Can't search for #{resource_type} resources. Skipping this resource type..."
        return nil
      end
      resource
    end

    def search_successful?
      response[:status] == 200
    end

    def valid_bundle_for_references?(bundle, resource_type)
      return log_skip("Can't get bundle for #{resource_type} resources. Skipping this resource type...") unless bundle

      entries = bundle.entry
      return log_skip("Bundle entry is nil. Skipping this resource type...") unless entries
      return log_skip("No #{resource_type} resources found. Skipping this resource type...") if entries.empty?

      true
    end

    def log_skip(message)
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
