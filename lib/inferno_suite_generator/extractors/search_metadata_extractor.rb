# frozen_string_literal: true

require_relative "search_definition_metadata_extractor"
require_relative "../core/generator_config_keeper"
require_relative "../core/fhirpath_expressions"

module InfernoSuiteGenerator
  class Generator
    class SearchMetadataExtractor
      COMBO_EXTENSION_URL =
        "http://hl7.org/fhir/StructureDefinition/capabilitystatement-search-parameter-combination"

      attr_accessor :resource_capabilities, :ig_resources, :profile_elements, :group_metadata, :config

      def initialize(resource_capabilities, ig_resources, profile_elements, group_metadata)
        self.resource_capabilities = resource_capabilities
        self.ig_resources = ig_resources
        self.profile_elements = profile_elements
        self.group_metadata = group_metadata
        self.config = Registry.get(:config_keeper)
        self.search_params_raw = FhirpathExpressions.cs_search_params.call(resource_capabilities)
      end

      def searches
        @searches ||= basic_searches + combo_searches

        handle_special_cases

        @searches
      end

      def conformance_expectation(search_param)
        # TODO: fix expectation extension finding
        FhirpathExpressions.search_param_expectation.call(search_param) || "SHALL"
      end

      def search_param_raw_to_metadata(search_param)
        {
          name: search_param.name,
          expectation: conformance_expectation(search_param)
        }
      end

      def basic_searches
        search_params_raw
          .select(&:search_param_expectation_available?)
          .reject(&:search_param_shall_be_excluded?)
          .map(&:search_param_raw_to_metadata)
      end

      def search_extensions
        resource_capabilities.extension
      end

      def combo_searches
        return [] if search_extensions.blank?

        combo_search_params = search_extensions
                              .select { |extension| extension.url == COMBO_EXTENSION_URL }
                              .select { |extension| config.search_params_expectation.include? conformance_expectation(extension) }
                              .map do |extension|
          names = extension.extension.select { |param| param.valueString.present? }.map(&:valueString)
          {
            expectation: conformance_expectation(extension),
            names:
          }
        end

        remove_params_to_ignore(combo_search_params)
      end

      def search_param_names
        searches.flat_map { |search| search[:names] }.uniq
      end

      def search_definitions
        search_param_names.each_with_object({}) do |name, definitions|
          definitions[name.to_sym] =
            SearchDefinitionMetadataExtractor.new(name, ig_resources, profile_elements,
                                                  group_metadata).search_definition
        end
      end

      def handle_special_cases
        @searches.map do |search|
          override_expectation = config.override_search_expectation(group_metadata[:profile_url],
                                                                    group_metadata[:resource], search[:names].first)
          next if override_expectation.nil?

          search[:expectation] = override_expectation["to"] if search[:expectation] == override_expectation["from"]
        end
      end

      private

      def search_param_expectation_available?(search_param)
        config.search_params_expectation.include? conformance_expectation(search_param)
      end
      
      def search_param_shall_be_excluded?(search_param)
        config.search_params_to_ignore.include? search_param.name
      end

      def remove_params_to_ignore(combo_search_params)
        # Remove combo search params if they are should be ignored, like _count, _sort, etc.
        combo_search_params.each do |combo_search_param|
          next unless combo_search_param[:names].any? { |sp| config.search_params_to_ignore.include? sp }

          current_search_params = combo_search_param[:names].filter do |sp|
            !config.search_params_to_ignore.include? sp
          end
          combo_search_param[:names] = current_search_params
        end

        # In some cases when we remove param to ignore, as the result we have duplicated combo params
        remove_combo_search_params_duplicates(combo_search_params)
      end

      def remove_combo_search_params_duplicates(combo_search_params)
        result = []
        combo_search_params.each do |combo_search_param|
          next if result.any? { |r| r[:names] == combo_search_param[:names] }
          next if combo_search_param[:names].length == 1

          expectation = use_the_high_expectation_search_param(combo_search_params.select do |sp|
            sp[:names] == combo_search_param[:names]
          end)
          combo_search_param[:expectation] = expectation
          result << combo_search_param
        end
        result
      end

      def use_the_high_expectation_search_param(combo_search_params)
        expectation_mapping = {
          "SHALL" => 3,
          "SHOULD" => 2,
          "MAY" => 1
        }
        expectations = combo_search_params.map { |combo_search_param| combo_search_param[:expectation] }
        expectations.max_by { |expectation| expectation_mapping[expectation] }
      end
    end
  end
end
