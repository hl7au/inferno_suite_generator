# frozen_string_literal: true

require_relative "../decorators/capability_statement_decorator"
require_relative "../decorators/fhir_search_response"

module InfernoSuiteGenerator
  # Shared logic for initializing the references keeper before create/update-new operations.
  # Fetches references from the FHIR server and from the user-provided mapping input,
  # so that resource reference paths can be replaced before sending requests.
  module ReferenceInitializer
    def initiate_references_keeper
      return if references_keeper.references.keys.any?

      add_references_from_server
      if respond_to?(:references_mapping_input, true) && references_mapping_input.present?
        references_keeper.add_references_from_input(references_mapping_input)
      end
    end

    private

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
  end
end
