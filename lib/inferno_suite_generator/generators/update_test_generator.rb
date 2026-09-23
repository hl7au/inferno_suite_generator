# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "basic_test_generator"
require_relative "../utils/registry"

module InfernoSuiteGenerator
  class Generator
    # The UpdateTestGenerator class generates test files for updating FHIR resources.
    # It extends BasicTestGenerator and handles the generation of test files specifically
    # for testing UPDATE operations against a FHIR server.
    class UpdateTestGenerator < BasicTestGenerator
      UPDATE_TEST_TYPE = "UPDATE".freeze
      UPDATE_CREATE_TEST_TYPE = "UPDATE_CREATE".freeze
      
      class << self

        
        def generate(ig_metadata, base_output_dir)
          ig_metadata.groups.each do |group|
            next if Registry.get(:config_keeper).exclude_resource?(group.profile_url, group.resource)
            next unless update_interaction(group).present?

            new(group, base_output_dir, ig_metadata, UPDATE_TEST_TYPE).generate
            new(group, base_output_dir, ig_metadata, UPDATE_CREATE_TEST_TYPE).generate if update_create_supported
          end
        end

        def update_interaction(group_metadata)
          group_metadata.interactions.find { |interaction| interaction[:code] == "update" }
        end

        def update_create_supported(group_metadata)
          group_metadata.update_create == true
        end
      end

      attr_reader :config, :test_type

      self.template_type = TEMPLATE_TYPES[:UPDATE]

      def initialize(group_metadata, base_output_dir, ig_metadata, test_type)
        super(group_metadata, base_output_dir, ig_metadata)
        @test_type = test_type
        @config = Registry.get(:config_keeper)
      end

      def update_interaction
        self.class.update_interaction(group_metadata)
      end

      def conformance_expectation
        update_interaction[:expectation]
      end

      def optional?
        conformance_expectation != "SHALL"
      end

      def humanized_option
        current_update_test_data["humanized_option"] if current_update_test_data
      end

      def test_id_option
        current_update_test_data["test_id_option"] if current_update_test_data
      end

      def executor
        current_update_test_data["executor"] if current_update_test_data
      end

      def references_mapping_should_be_shown?
        test_type == UPDATE_CREATE_TEST_TYPE && group_metadata.references.present?
      end

      def resource_to_create_filter
        config.resource_to_create_filter(group_metadata.profile_url, group_metadata.resource) || nil
      end

      private

      def current_update_test_data
        case @test_type
        when UPDATE_TEST_TYPE
          {
            "humanized_option" => "Update",
            "test_id_option" => "update",
            "executor" => "perform_update_test"
          }
        when UPDATE_CREATE_TEST_TYPE
          {
            "humanized_option" => "Update (Create)",
            "test_id_option" => "update_new",
            "executor" => "perform_update_new_test"
          }
        end
      end
    end
  end
end
