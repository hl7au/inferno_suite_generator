# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "search_test_generator"
require_relative "../utils/helpers"
require_relative "../utils/registry"
require_relative "../utils/multiple_or_search_test_generator_helpers"
require_relative "../utils/generic"
require_relative "../utils/generator_utils"

module InfernoSuiteGenerator
  class Generator
    # The MultipleOrSearchTestGenerator class generates test files for search FHIR resources.
    # It extends SearchTestGenerator and handles the generation of test files specifically
    # for testing multiple OR search operations against a FHIR server.
    class MultipleOrSearchTestGenerator < SearchTestGenerator
      include MultipleOrSearchTestGeneratorHelpers
      include GenericUtils
      include GeneratorUtils

      # Holds base_output_dir and ig_metadata to avoid passing the same pair to multiple methods.
      GenerationContext = Struct.new(:base_output_dir, :ig_metadata)

      class << self
        def generate(ig_metadata, base_output_dir)
          ctx = GenerationContext.new(base_output_dir:, ig_metadata:)
          ig_metadata.search_groups.each { |group| generate_test(group, ctx) }
        end

        def generate_test(group, ctx)
          search_definitions = group.search_definitions
          search_definitions.each_key do |search_key|
            next unless multiple_or_test?(group, search_key)

            new(search_key.to_s, group, search_definitions[search_key], ctx).generate
          end
        end

        def multiple_or_test?(group, search_key)
          group.search_definitions[search_key].key?(:multiple_or) && search_key.to_s != "patient"
        end
      end

      attr_reader :search_name, :group_metadata, :search_metadata, :base_output_dir, :ig_metadata

      self.template_type = TEMPLATE_TYPES[:MULTIPLE_OR_SEARCH]

      def initialize(search_name, group_metadata, search_metadata, ctx)
        super(group_metadata, search_metadata, ctx.base_output_dir, ctx.ig_metadata)
        self.search_name = search_name
      end

      def search_identifier
        search_name.to_s.tr("-", "_")
      end

      def search_title
        search_identifier
      end

      def conformance_expectation
        # NOTE: https://github.com/hl7au/au-fhir-core-inferno/issues/61
        return "SHOULD" if search_name == "status" && %w[Procedure Observation].include?(resource_type)

        search_metadata[:multiple_or]
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

      private

      attr_writer :search_name, :group_metadata, :search_metadata, :base_output_dir, :ig_metadata
    end
  end
end
