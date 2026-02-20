# frozen_string_literal: true

module InfernoSuiteGenerator
  # Provides helper methods for generating "OR" search tests within the InfernoSuiteGenerator.
  module MultipleOrSearchTestGeneratorHelpers
    # Configuration class for storing search test parameters including property, value, and condition
    class SearchTestConfig
      attr_reader :property, :value, :condition

      def initialize(property:, value:, condition:)
        @property = property
        @value = value
        @condition = condition
      end

      def add_property(properties)
        properties[property] = value if condition
      end
    end

    def saves_resources_to_scratch?
      first_search? || Registry.get(:config_keeper).keep_all_resources_on_search?(
        group_metadata.profile_url, group_metadata.resource
      )
    end

    def simple_search_test_configs
      [
        { property: :first_search, value: "true", condition: first_search? },
        { property: :saves_resources_to_scratch, value: "true", condition: saves_resources_to_scratch? },
        { property: :fixed_value_search, value: "true", condition: fixed_value_search? },
        { property: :resource_type, value: "'#{resource_type}'", condition: true },
        { property: :search_param_names, value: search_param_names, condition: true },
        { property: :saves_delayed_references, value: "true", condition: saves_delayed_references? },
        { property: :test_medication_inclusion, value: "true", condition: test_medication_inclusion? },
        { property: :test_reference_variants, value: "true", condition: test_reference_variants? }
      ]
    end

    def complex_search_test_configs
      [
        { property: :multiple_or_search_params, value: required_multiple_or_search_params_string,
          condition: required_multiple_or_search_params.present? },
        { property: :optional_multiple_or_search_params, value: optional_multiple_or_search_params_string,
          condition: optional_multiple_or_search_params.present? },
        { property: :search_by_target_resource_data, value: "true", condition: search_by_target_resource? }
      ]
    end

    def search_by_target_resource?
      Registry.get(:config_keeper).multiple_or_and_search_by_target_resource?(
        group_metadata.profile_url, resource_type, search_param_names
      )
    end

    def search_test_config_objects
      (simple_search_test_configs + complex_search_test_configs).map { |conf| SearchTestConfig.new(**conf) }
    end

    def search_properties
      {}.tap do |properties|
        search_test_config_objects.each do |config|
          config.add_property(properties)
        end
      end
    end

    def description
      Helpers.multiple_test_description("OR", conformance_expectation, search_param_name_string, resource_type,
                                        url_version)
    end

    def test_medication_inclusion?
      %w[MedicationRequest MedicationDispense].include?(resource_type)
    end

    def test_post_search?
      first_search?
    end

    def optional?
      %w[SHOULD MAY].include?(conformance_expectation)
    end

    def search_definition(name)
      group_metadata.search_definitions[name.to_sym]
    end

    def saves_delayed_references?
      first_search? && group_metadata.delayed_references.present?
    end

    def required_multiple_or_search_params
      @required_multiple_or_search_params ||=
        search_definition(search_name)[:multiple_or] == "SHALL"
    end

    def optional_multiple_or_search_params
      @optional_multiple_or_search_params ||=
        search_definition(search_name)[:multiple_or] == "SHOULD"
    end

    def required_multiple_or_search_params_string
      required_multiple_or_search_params
    end

    def optional_multiple_or_search_params_string
      optional_multiple_or_search_params
    end

    def required_comparators_string
      array_of_strings(required_comparators.keys)
    end

    def test_reference_variants?
      first_search? && search_param_names.include?("patient")
    end
  end
end
