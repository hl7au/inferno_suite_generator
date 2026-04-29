# frozen_string_literal: true

require_relative "../utils/fhir_resource_navigation"

module InfernoSuiteGenerator
  # This class is used to check if the mandatory and must-support elements are present in the resources
  class MSChecker
    include FHIRResourceNavigation

    def initialize(group_metadata, config = {})
      @metadata = group_metadata
      @config = config
    end

    def elements_present_statuses(resources = [])
      must_support_elements.map do |element_definition|
        build_element_status(element_definition, mandatory_elements_clean, resources)
      end
    end

    private

    def mandatory_elements_clean
      @metadata.mandatory_elements.map do |element|
        element.gsub("#{@metadata.resource}.", "")
      end
    end

    def build_element_status(element_definition, mandatory_elements, resources)
      path = element_definition[:path]
      {
        definition: element_definition,
        path:,
        mandatory: mandatory_elements.include?(path),
        present: resources.any? { |resource| must_support_element_present?(element_definition, resource) }
      }
    end

    def must_support_element_present?(element_definition, resource)
      path = element_definition[:path]
      value_found = value_found?(resource, path, element_definition)
      value_found.present? || value_found == false
    end

    def must_support_elements
      prepare_uscdi_ms(:elements)
    end

    def prepare_uscdi_ms(metadata_key)
      return ms_exclude_usdi(metadata_key) if exclude_uscdi_only_test?

      @metadata.must_supports&.dig(metadata_key) || []
    end

    def exclude_uscdi_only_test?
      !!@config["exclude_uscdi_only_test"]
    end

    def ms_exclude_usdi(metadata_key)
      @metadata.must_supports&.dig(metadata_key)&.reject { |item| item[:uscdi_only] } || []
    end

    def value_found?(resource, path, element_definition)
      find_a_value_at(resource, path) do |value|
        value_without_extensions =
          value.respond_to?(:to_hash) ? value.to_hash.except("extension") : value

        (value_without_extensions.present? || value_without_extensions == false) &&
          (element_definition[:fixed_value].blank? || value == element_definition[:fixed_value])
      end
    end
  end
end
