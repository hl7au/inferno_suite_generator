# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "search_test_generator"
require_relative "../utils/registry"

module InfernoSuiteGenerator
  class Generator
    class IncludeSearchTestGenerator < SearchTestGenerator
      class << self
        def generate(ig_metadata, base_output_dir)
          config = Registry.get(:config_keeper)
          filtered_groups(ig_metadata, config).each do |group|
            include_searches = group_include_searches(group, config)
            next unless include_searches.present?
            group.searches.each do |search|
              filtered_include_search = include_searches.find { |include_search| include_search["names"].sort == search[:names].sort }
              next unless filtered_include_search.present?
              new(group, search, base_output_dir, filtered_include_search, ig_metadata).generate
            end
          end
        end

        private

        def filtered_groups(ig_metadata, config)
          ig_metadata.groups.reject do |group|
            config.exclude_resource?(group.profile_url, group.resource)
          end
        end

        def group_include_searches(group, config)
          config.extra_searches(group.profile_url, group.resource).select { |search| search["type"] == "include" }
        end
      end

      attr_accessor :group_metadata, :search_metadata, :base_output_dir, :include_param

      self.template_type = TEMPLATE_TYPES[:INCLUDE]

      def initialize(group_metadata, search_metadata, base_output_dir, include_param, ig_metadata)
        self.group_metadata = group_metadata
        self.search_metadata = search_metadata
        self.base_output_dir = base_output_dir
        self.include_param = include_param
        self.ig_metadata = ig_metadata
      end

      def search_identifier
        search_metadata[:names].join("_").tr("-", "_")
      end

      def search_title
        search_identifier.camelize
      end

      def conformance_expectation
        "SHOULD"
      end

      def optional?
        true
      end

      def needs_patient_id?
        true
      end

      def search_properties
        {}.tap do |properties|
          properties[:resource_type] = "'#{resource_type}'"
          properties[:saves_delayed_references] = "true" if saves_delayed_references?
          properties[:search_param_names] = search_param_names_array
          properties[:includes] = includes if group_metadata.include_params.present?
          properties[:use_any_data_for_search] = true
        end
      end

      def target_resources_string
        includes.map { |include| include["target_resource"] }.join(", ")
      end

      def include_params_string
        includes.map { |include| include["parameter"] }.join(", ")
      end

      def search_param_names_string
        search_param_names.join(", ")
      end

      def search_param_names_lodash_string
        search_param_names.join("_")
      end

      def title
        "Server returns #{target_resources_string} resources from #{resource_type} search by #{search_param_names_string} and #{include_params_string}"
      end

      def description
        <<~DESCRIPTION.gsub(/\n{3,}/, "\n\n")
          This test will perform a search by #{search_param_names_string} and the _include=#{include_params_string}

          Test will pass if a #{target_resources_string} resources are found in the response.
        DESCRIPTION
      end

      def search_method
        "run_include_test"
      end
    end
  end
end
