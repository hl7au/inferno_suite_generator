# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "search_test_generator"
require_relative "../utils/helpers"
require_relative "../utils/registry"

module InfernoSuiteGenerator
  class Generator
    class MultipleAndSearchTestGenerator < SearchTestGenerator
      class << self
        def generate(ig_metadata, base_output_dir)
          ig_metadata.groups
                     .select { |group| group.searches.present? }
                     .reject do |group|
            Registry.get(:config_keeper).exclude_resource?(group.profile_url, group.resource)
          end
                     .each do |group|
            group.search_definitions.each_key do |search_key|
              if group.search_definitions[search_key].key?(:multiple_and) && search_key.to_s != "patient"
                new(search_key.to_s, group, group.search_definitions[search_key], base_output_dir,
                    ig_metadata).generate
              end
            end
          end
        end
      end

      attr_accessor :search_name, :group_metadata, :search_metadata, :base_output_dir, :ig_metadata

      self.template_type = TEMPLATE_TYPES[:MULTIPLE_AND_SEARCH]

      def initialize(search_name, group_metadata, search_metadata, base_output_dir, ig_metadata)
        self.search_name = search_name
        self.group_metadata = group_metadata
        self.search_metadata = search_metadata
        self.base_output_dir = base_output_dir
        self.ig_metadata = ig_metadata
      end

      def search_identifier
        search_name.to_s.tr("-", "_")
      end

      def search_title
        search_identifier
      end

      def conformance_expectation
        search_metadata[:multiple_and]
      end

      def first_search?
        group_metadata.searches.first == search_metadata
      end

      def fixed_value_search?
        first_search? && search_metadata[:names] != ["patient"] &&
          !group_metadata.delayed? && resource_type != "Patient"
      end

      def fixed_value_search_param_name
        (search_metadata[:names] - [:patient]).first
      end

      def search_param_name_string
        search_name
      end

      def needs_patient_id?
        true
      end

      def search_param_names
        [search_name]
      end

      def search_param_names_array
        array_of_strings(search_param_names)
      end

      def path_for_value(path)
        path == "class" ? "local_class" : path
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

      def required_multiple_and_search_params
        @required_multiple_and_search_params ||=
          search_definition(search_name)[:multiple_and] == "SHALL"
      end

      def optional_multiple_and_search_params
        @optional_multiple_and_search_params ||=
          search_definition(search_name)[:multiple_and] == "SHOULD"
      end

      def required_multiple_and_search_params_string
        required_multiple_and_search_params
      end

      def optional_multiple_and_search_params_string
        optional_multiple_and_search_params
      end

      def required_comparators_string
        array_of_strings(required_comparators.keys)
      end

      def test_reference_variants?
        first_search? && search_param_names.include?("patient")
      end

      def test_medication_inclusion?
        %w[MedicationRequest MedicationDispense].include?(resource_type)
      end

      def test_post_search?
        first_search?
      end

      def search_properties
        {}.tap do |properties|
          properties[:first_search] = "true" if first_search?
          properties[:fixed_value_search] = "true" if fixed_value_search?
          properties[:resource_type] = "'#{resource_type}'"
          properties[:search_param_names] = search_param_names
          properties[:saves_delayed_references] = "true" if saves_delayed_references?
          properties[:test_medication_inclusion] = "true" if test_medication_inclusion?
          properties[:test_reference_variants] = "true" if test_reference_variants?
          if required_multiple_and_search_params.present?
            properties[:multiple_and_search_params] =
              required_multiple_and_search_params_string
          end
          if optional_multiple_and_search_params.present?
            properties[:optional_multiple_and_search_params] =
              optional_multiple_and_search_params_string
          end
          if Registry.get(:config_keeper).multiple_or_and_search_by_target_resource?(
            group_metadata.profile_url, resource_type, search_param_names
          )
            properties[:search_by_target_resource_data] =
              "true"
          end
        end
      end

      def description
        Helpers.multiple_test_description("AND", conformance_expectation, search_param_name_string, resource_type,
                                          url_version)
      end
    end
  end
end
