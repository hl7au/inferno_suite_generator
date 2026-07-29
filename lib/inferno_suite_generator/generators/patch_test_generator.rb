# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "basic_test_generator"
require_relative "../utils/registry"
require_relative "../utils/generic"
require_relative "../decorators/parameters_parameter_decorator"
require_relative "../decorators/bundle_entry_decorator"
require_relative "../utils/patch_test_generator_helpers"

module InfernoSuiteGenerator
  class Generator
    # The PatchTestGenerator class generates test files for patching FHIR resources.
    # It extends BasicTestGenerator and handles the generation of test files specifically
    # for testing PATCH operations against a FHIR server.
    class PatchTestGenerator < BasicTestGenerator
      include GenericUtils
      include PatchTestGeneratorHelpers

      # PATCH_TEST_TYPES = %w[XML JSON FHIRPathXML FHIRPathJSON].freeze
      PATCH_TEST_TYPES = %w[FHIRPathJSON].freeze

      class << self
        def generate(ig_metadata, base_output_dir, ig_resources = nil)
          ig_metadata.groups.each do |group|
            group_generate(group, base_output_dir, {
                             ig_metadata:, ig_resources:
                           })
          end
        end

        def group_generate(group, base_output_dir, ig_data)
          return if skip_generate?(group)

          PATCH_TEST_TYPES.each do |patch_option|
            new(group, base_output_dir, ig_data[:ig_metadata], patch_option, ig_data[:ig_resources]).generate
          end
        end

        def skip_generate?(group_metadata)
          [Registry.get(:config_keeper).exclude_resource?(group_metadata.profile_url, group_metadata.resource),
           !patch_interaction(group_metadata).present?].any?
        end

        def patch_interaction(group_metadata)
          group_metadata.interactions.find { |interaction| interaction[:code] == "patch" }
        end
      end

      attr_reader :ig_resources, :config, :test_type

      self.template_type = TEMPLATE_TYPES[:PATCH]

      def initialize(group_metadata, base_output_dir, ig_metadata, test_type, ig_resources = nil)
        super(group_metadata, base_output_dir, ig_metadata)
        @test_type = test_type
        @ig_resources = ig_resources
        @config = Registry.get(:config_keeper)
      end

      def patch_interaction
        self.class.patch_interaction(group_metadata)
      end

      def patch_checks
        config.patch_checks
      end

      def conformance_expectation
        patch_interaction[:expectation]
      end

      def create_patch_data
        return unless patch_entry

        [patchset]
      end

      def humanized_option
        return unless current_test_data&.key?("humanized_option")

        current_test_data["humanized_option"]
      end

      def test_id_option
        current_test_data["test_id_option"] if current_test_data&.key?("test_id_option")
      end

      def patchset
        current_test_data["patchset"] if current_test_data&.key?("patchset")
      end

      def executor
        current_test_data["executor"] if current_test_data&.key?("executor")
      end

      def ids_input_data
        return unless needs_ids_input?

        {
          id: data[:id].to_sym,
          title: data[:title],
          description: data[:description],
          default: data[:default]
        }
      end

      private

      def data
        return unless needs_ids_input?

        snake_case_resource_type = camel_to_snake(resource_type)
        description = "Comma separated list of #{snake_case_resource_type.tr("_", " ")}"
        constants = config.constants

        {
          id: :"#{snake_case_resource_type}_ids",
          title: "#{resource_type} IDs",
          description:,
          default: constants["patch_ids.#{snake_case_resource_type}"] || ""
        }
      end

      def needs_ids_input?
        group_metadata.needs_ids_input?
      end
    end
  end
end
