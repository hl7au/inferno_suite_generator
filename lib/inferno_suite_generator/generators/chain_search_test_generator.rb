# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "../utils/generator_utils"
require_relative "search_test_generator"

module InfernoSuiteGenerator
  class Generator
    class ChainSearchTestGenerator < SearchTestGenerator
      include GeneratorUtils

      class << self
        def generate(ig_metadata, base_output_dir)
          ig_metadata.groups
                     .select { |group| group.searches.present? }
                     .reject do |group|
            Registry.get(:config_keeper).exclude_resource?(group.profile_url, group.resource)
          end
                     .each do |group|
            group.search_definitions.each_key do |search_key|
              current_search_definition = group.search_definitions[search_key]
              next unless current_search_definition.key?(:chain) && current_search_definition[:chain].length.positive?

              current_search_definition[:chain].each do |chain_item|
                new(
                  search_key.to_s,
                  group,
                  group.search_definitions[search_key],
                  base_output_dir,
                  chain_item,
                  ig_metadata
                ).generate
              end
            end
          end
        end
      end

      attr_accessor :search_name, :group_metadata, :search_metadata, :base_output_dir, :chain_item, :ig_metadata

      self.template_type = TEMPLATE_TYPES[:CHAIN_SEARCH]

      def initialize(search_name, group_metadata, search_metadata, base_output_dir, chain_item, ig_metadata)
        self.search_name = search_name
        self.group_metadata = group_metadata
        self.search_metadata = search_metadata
        self.base_output_dir = base_output_dir
        self.chain_item = chain_item
        self.ig_metadata = ig_metadata
      end

      def search_identifier
        search_name.to_s.tr("-", "_")
      end

      def search_title
        search_identifier.camelize
      end

      def conformance_expectation
        chain_item[:expectation]
      end

      def search_param_names
        ["#{search_name}:#{chain_item[:target]}.#{chain_item[:chain]}"]
      end

      def search_param_names_array
        array_of_strings(search_param_names)
      end

      def search_param_name_string
        search_name
      end

      def search_properties
        {}.tap do |properties|
          properties[:resource_type] = "'#{resource_type}'"
          properties[:search_param_names] = search_param_names_array
          properties[:attr_paths] = attribute_paths
        end
      end

      def attribute_paths
        search_metadata[:paths]
      end

      def optional?
        conformance_expectation != "SHALL"
      end

      def search_definition(name)
        group_metadata.search_definitions[name.to_sym]
      end

      def title
        "Server returns valid results for #{resource_type} search by #{search_param_name_string} (chained parameters)"
      end

      def description
        <<~DESCRIPTION.gsub(/\n{3,}/, "\n\n")
          A server #{conformance_expectation} support searching by
          #{search_param_names.first} on the #{resource_type} resource. This test
          will pass if the server returns a success response to the request.

          #{capability_statement_reference_string}
        DESCRIPTION
      end
    end
  end
end
