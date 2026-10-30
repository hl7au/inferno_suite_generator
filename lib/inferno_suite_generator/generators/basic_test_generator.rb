# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "../utils/generator_constants"
require_relative "../utils/registry"
require_relative "../utils/generic"

module InfernoSuiteGenerator
  class Generator
    class BasicTestGenerator
      include GeneratorConstants
      include GenericUtils

      attr_reader :group_metadata, :base_output_dir, :ig_metadata

      class_attribute :template_type
      def initialize(group_metadata, base_output_dir, ig_metadata)
        @group_metadata = group_metadata
        @base_output_dir = base_output_dir
        @ig_metadata = ig_metadata
      end

      def suite_module_name
        config = Registry.get(:config_keeper)
        config.suite_module_name
      end

      def template
        @template ||= File.read(File.join(__dir__, "../templates", template_file_name))
      end

      def output_file_directory
        File.join(base_output_dir, profile_identifier)
      end

      def output_file_name
        File.join(output_file_directory, base_output_file_name)
      end

      def base_output_file_name
        "#{class_name.underscore}.rb"
      end

      def output
        @output ||= ERB.new(template).result(binding)
      end

      def profile_identifier
        Naming.snake_case_for_profile(group_metadata)
      end

      def module_name
        "#{ig_metadata.ig_module_name_prefix}#{group_metadata.reformatted_version.upcase}"
      end

      def resource_type
        group_metadata.resource
      end

      def filter_set
        config = Registry.get(:config_keeper)
        config.filter_set(group_metadata.profile_url, group_metadata.resource)
      end

      def test_id
        case template_type
        when TEMPLATE_TYPES[:READ], TEMPLATE_TYPES[:VALIDATION], TEMPLATE_TYPES[:REFERENCE_RESOLUTION], TEMPLATE_TYPES[:MUST_SUPPORT], TEMPLATE_TYPES[:CREATE]
          "#{basic_test_id}_#{TEST_ID_SUFFIXES[template_type]}"
        when TEMPLATE_TYPES[:PATCH], TEMPLATE_TYPES[:UPDATE]
          "#{basic_test_id}_#{test_id_option}_#{TEST_ID_SUFFIXES[template_type]}"
        when TEMPLATE_TYPES[:MULTIPLE_AND_SEARCH], TEMPLATE_TYPES[:SEARCH], TEMPLATE_TYPES[:CHAIN_SEARCH],
             TEMPLATE_TYPES[:MULTIPLE_OR_SEARCH], TEMPLATE_TYPES[:PROVENANCE_REVINCLUDE_SEARCH]
          "#{basic_test_id_with_search}_#{TEST_ID_SUFFIXES[template_type]}"
        when TEMPLATE_TYPES[:INCLUDE]
          "#{basic_test_id}_#{search_param_names_lodash_string}_include_#{search_identifier.downcase}_search_test"
        when TEMPLATE_TYPES[:SPECIAL_IDENTIFIER_SEARCH]
          "#{basic_test_id}_#{search_identifier}_#{special_identifier["display"].delete("-").downcase}_search_test"
        when TEMPLATE_TYPES[:SPECIAL_IDENTIFIER_CHAIN_SEARCH]
        when TEMPLATE_TYPES[:SUITE]
        when TEMPLATE_TYPES[:GROUP]
        else
          raise("Unknown test_id for type: #{template_type}")
        end
      end

      def class_name
        case template_type
        when TEMPLATE_TYPES[:READ], TEMPLATE_TYPES[:VALIDATION], TEMPLATE_TYPES[:REFERENCE_RESOLUTION], TEMPLATE_TYPES[:MUST_SUPPORT], TEMPLATE_TYPES[:CREATE]
          "#{basic_class_name}#{CLASS_NAME_SUFFIXES[template_type]}"
        when TEMPLATE_TYPES[:PATCH], TEMPLATE_TYPES[:UPDATE]
          "#{basic_class_name}#{test_type}#{CLASS_NAME_SUFFIXES[template_type]}"
        when TEMPLATE_TYPES[:SEARCH], TEMPLATE_TYPES[:CHAIN_SEARCH], TEMPLATE_TYPES[:PROVENANCE_REVINCLUDE_SEARCH]
          "#{basic_class_name_with_search}#{CLASS_NAME_SUFFIXES[template_type]}"
        when TEMPLATE_TYPES[:MULTIPLE_AND_SEARCH], TEMPLATE_TYPES[:MULTIPLE_OR_SEARCH]
          "#{basic_class_name_with_search_capitalize}#{CLASS_NAME_SUFFIXES[template_type]}"
        when TEMPLATE_TYPES[:INCLUDE]
          "#{basic_class_name_with_search}Include#{includes.first["target_resource"]}Test"
        when TEMPLATE_TYPES[:SPECIAL_IDENTIFIER_SEARCH]
          "#{basic_class_name_with_search}#{special_identifier["display"].delete("-")}SearchTest"
        when TEMPLATE_TYPES[:SUITE]
          "#{ig_metadata.ig_module_name_prefix}TestSuite"
        when TEMPLATE_TYPES[:GROUP]
          "#{Naming.upper_camel_case_for_profile(group_metadata)}Group"
        when TEMPLATE_TYPES[:SPECIAL_IDENTIFIER_CHAIN_SEARCH]
        else
          raise("Unknown class_name for type: #{template_type}")
        end
      end

      def capability_statement_reference_string
        config = Registry.get(:config_keeper)

        "[#{config.title} Server CapabilityStatement](#{config.cs_version_specific_url})"
      end

      def generate
        FileUtils.mkdir_p(output_file_directory)
        File.write(output_file_name, output)

        group_metadata.add_test(
          id: test_id,
          file_name: base_output_file_name,
          kind: template_type,
          **test_details
        )
      end

      # What tells this test apart from other tests of its kind in the group, recorded by add_test.
      def test_details
        case template_type
        when TEMPLATE_TYPES[:PATCH], TEMPLATE_TYPES[:UPDATE]
          { option: test_id_option }
        else
          {}
        end
      end

      private

      def template_file_name
        TEMPLATE_FILES_MAP[template_type] || raise("Unknown template type: #{template_type}")
      end

      def basic_test_id
        "#{ig_metadata.ig_test_id_prefix}_#{group_metadata.reformatted_version}_#{profile_identifier}"
      end

      def basic_test_id_with_search
        "#{basic_test_id}_#{search_identifier}"
      end

      def basic_class_name
        Naming.upper_camel_case_for_profile(group_metadata)
      end

      def basic_class_name_with_search
        "#{basic_class_name}#{search_title}"
      end

      def basic_class_name_with_search_capitalize
        "#{basic_class_name}#{search_title.capitalize}"
      end

      def url_version
        group_metadata.version.delete_prefix("v")
      end
    end
  end
end
