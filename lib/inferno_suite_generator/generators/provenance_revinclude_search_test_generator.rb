# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "basic_test_generator"
require_relative "../utils/registry"
require_relative "../utils/generator_utils"

module InfernoSuiteGenerator
  class Generator
    class ProvenanceRevincludeSearchTestGenerator < BasicTestGenerator
      include GeneratorUtils

      class << self
        def generate(ig_metadata, base_output_dir)
          ig_metadata.groups
                     .reject do |group|
                       Registry.get(:config_keeper).exclude_resource?(group.profile_url, group.resource)
                     end
                     .select { |group| group.revincludes.include? "Provenance:target" }
                     .each { |group| new(group, group.searches.first, base_output_dir, ig_metadata).generate }
        end
      end

      attr_accessor :group_metadata, :search_metadata, :base_output_dir, :ig_metadata

      self.template_type = TEMPLATE_TYPES[:PROVENANCE_REVINCLUDE_SEARCH]

      def initialize(group_metadata, search_metadata, base_output_dir, ig_metadata)
        self.group_metadata = group_metadata
        self.search_metadata = search_metadata
        self.base_output_dir = base_output_dir
        self.ig_metadata = ig_metadata
      end

      def search_identifier
        "provenance_revinclude"
      end

      def search_title
        search_identifier.camelize
      end

      def first_search?
        group_metadata.searches.first == search_metadata
      end

      def fixed_value_search?
        search_metadata[:names] != ["patient"] &&
          !group_metadata.delayed? && resource_type != "Patient"
      end

      def fixed_value_search_param_name
        (search_metadata[:names] - [:patient]).first
      end

      def search_param_name_string
        "#{search_metadata[:names].join(" + ")} + revInclude:Provenance:target"
      end

      def needs_patient_id?
        search_metadata[:names].include?("patient") ||
          (resource_type == "Patient" && search_metadata[:names].include?("_id"))
      end

      def search_param_names
        search_params.map { |param| param[:name] }
      end

      def search_param_names_array
        array_of_strings(search_param_names)
      end

      def path_for_value(path)
        path == "class" ? "local_class" : path
      end

      def required_comparators_for_param(name)
        search_definition(name)[:comparators].select { |_comparator, expectation| expectation == "SHALL" }
      end

      # def patient_id_param?(param)
      #   param[:name] == 'patient' ||
      #     (resource_type == 'Patient' && param[:name] == '_id')
      # end

      def search_definition(name)
        group_metadata.search_definitions[name.to_sym]
      end

      def saves_delayed_references?
        first_search? && group_metadata.delayed_references.present?
      end

      def possible_status_search?
        !search_metadata[:names].include?("status") && group_metadata.search_definitions.key?(:status)
      end

      def token_search_params_string
        array_of_strings(token_search_params)
      end

      def required_comparators_string
        array_of_strings(required_comparators.keys)
      end

      def saves_resources_to_scratch?
        first_search? || Registry.get(:config_keeper).keep_all_resources_on_search?(
          group_metadata.profile_url, group_metadata.resource
        )
      end

      def search_properties
        {}.tap do |properties|
          properties[:first_search] = "true" if first_search?
          properties[:saves_resources_to_scratch] = "true" if saves_resources_to_scratch?
          properties[:fixed_value_search] = "true" if fixed_value_search?
          properties[:resource_type] = "'#{resource_type}'"
          properties[:search_param_names] = search_param_names_array
          properties[:possible_status_search] = "true" if possible_status_search?
        end
      end
    end
  end
end
