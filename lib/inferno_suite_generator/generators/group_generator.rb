# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "basic_test_generator"
require_relative "../utils/helpers"
require_relative "../utils/registry"

module InfernoSuiteGenerator
  class Generator
    # Writes one group file and its metadata.yml per profile group, with any added
    # Markdown appended to the group and test descriptions.
    class GroupGenerator < BasicTestGenerator
      class << self
        def generate(ig_metadata, base_output_dir, descriptions = {})
          ig_metadata.ordered_groups.compact.each do |group|
            next if Registry.get(:config_keeper).exclude_resource?(group.profile_url, group.resource)

            added = descriptions.fetch(group, {})
            # Kit subclasses may keep a three-argument initialize, so pass descriptions only when there are some.
            args = [group, base_output_dir, ig_metadata]
            args << added if added.present?
            new(*args).generate
          end
        end
      end

      attr_accessor :group_metadata, :base_output_dir, :ig_metadata, :descriptions

      self.template_type = TEMPLATE_TYPES[:GROUP]

      def initialize(group_metadata, base_output_dir, ig_metadata, descriptions = {})
        super(group_metadata, base_output_dir, ig_metadata)
        self.descriptions = descriptions
      end

      def base_metadata_file_name
        "metadata.yml"
      end

      def title
        group_metadata.title
      end

      def short_description
        group_metadata.short_description
      end

      def output_file_name
        File.join(base_output_dir, base_output_file_name)
      end

      def metadata_file_name
        File.join(base_output_dir, profile_identifier, base_metadata_file_name)
      end

      def group_id
        "#{ig_metadata.ig_test_id_prefix}_#{group_metadata.reformatted_version}_#{profile_identifier}"
      end

      def search_validation_resource_type
        "#{resource_type} resources"
      end

      def profile_name
        group_metadata.profile_name
      end

      def profile_url
        group_metadata.profile_url
      end

      def optional?
        false
      end

      def generate
        File.write(output_file_name, output)
        group_metadata.id = group_id
        group_metadata.file_name = base_output_file_name
        File.write(metadata_file_name, YAML.dump(group_metadata.to_hash))
      end

      def test_id_list
        @test_id_list ||= group_metadata.tests.map { |test| test[:id] }
      end

      def test_file_list
        @test_file_list ||=
          group_metadata.tests.map do |test|
            name_without_suffix = test[:file_name].delete_suffix(".rb")
            name_without_suffix.start_with?("..") ? name_without_suffix : "#{profile_identifier}/#{name_without_suffix}"
          end
      end

      def required_searches
        group_metadata.searches.select { |search| search[:expectation] == "SHALL" }
      end

      def search_param_name_string
        required_searches
          .map { |search| search[:names].join(" + ") }
          .map { |names| "* #{names}" }
          .join("\n")
      end

      def description
        Helpers.get_group_description_text(title, resource_type, profile_name, group_metadata.version, profile_url,
                                           required_searches, search_param_name_string,
                                           search_validation_resource_type, resource_type)
      end

      def group_description
        added = added_description(:group)
        added ? "#{description}\n#{added}\n" : description
      end

      # Added text goes inside a %( ) literal in the group file. CR is written as \r,
      # because Ruby turns a CRLF in source into LF.
      def added_description(key)
        text = descriptions[key]
        return if text.blank?

        text.gsub(/[\\()]|#(?=[{@$])/) { |char| "\\#{char}" }.gsub("\r", '\r')
      end
    end
  end
end
