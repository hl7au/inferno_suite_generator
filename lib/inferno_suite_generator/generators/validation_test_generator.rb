# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "basic_test_generator"
require_relative "../utils/registry"

module InfernoSuiteGenerator
  class Generator
    class ValidationTestGenerator < BasicTestGenerator
      class << self
        def generate(ig_metadata, base_output_dir)
          all_groups = ig_metadata.groups
          filtered_groups = all_groups.reject do |group|
            config = Registry.get(:config_keeper)
            config.exclude_resource?(group.profile_url, group.resource)
          end
          filtered_groups.each do |group|
            new(group, ig_metadata, base_output_dir:).generate
          end
        end
      end

      attr_accessor :group_metadata, :medication_request_metadata, :base_output_dir, :ig_metadata

      self.template_type = TEMPLATE_TYPES[:VALIDATION]

      def initialize(group_metadata, ig_metadata, medication_request_metadata = nil, base_output_dir:)
        self.group_metadata = group_metadata
        self.ig_metadata = ig_metadata
        self.medication_request_metadata = medication_request_metadata
        self.base_output_dir = base_output_dir
      end

      def output_file_directory
        File.join(base_output_dir, directory_name)
      end

      def directory_name
        Naming.snake_case_for_profile(medication_request_metadata || group_metadata)
      end

      def profile_url
        group_metadata.profile_url
      end

      def profile_name
        group_metadata.profile_name
      end

      def profile_version
        group_metadata.profile_version
      end

      def conformance_expectation
        read_interaction[:expectation]
      end

      def skip_if_empty
        # Return true if a system must demonstrate at least one example of the resource type.
        # This drives omit vs. skip result statuses in this test.
        resource_type != "Medication"
      end

      def validation_message_level_overrides
        Registry.get(:config_keeper).validation_message_level_overrides
      end

      def generate
        FileUtils.mkdir_p(output_file_directory)
        File.write(output_file_name, output)

        test_metadata = {
          id: test_id,
          file_name: base_output_file_name
        }

        group_metadata.add_test(**test_metadata)
      end

      def description
        <<~DESCRIPTION
          #{description_intro}
          It verifies the presence of mandatory elements and that elements with
          required bindings contain appropriate values. CodeableConcept element
          bindings will fail if none of their codings have a code/system belonging
          to the bound ValueSet. Quantity, Coding, and code element bindings will
          fail if their code/system are not found in the valueset.
        DESCRIPTION
      end

      def description_intro
        if resource_type == "Medication"
          <<~MEDICATION_INTRO
            This test verifies resources returned from previous tests conform to
            the [#{profile_name}](#{profile_url}).
          MEDICATION_INTRO
        else
          <<~GENERIC_INTRO
            This test verifies resources returned from the first search conform to
            the [#{profile_name}](#{profile_url}).
            If at least one resource from the first search is invalid, the test will fail.
          GENERIC_INTRO
        end
      end
    end
  end
end
