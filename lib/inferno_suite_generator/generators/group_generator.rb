# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "basic_test_generator"
require_relative "../utils/helpers"
require_relative "../utils/registry"

module InfernoSuiteGenerator
  class Generator
    class GroupGenerator < BasicTestGenerator
      class << self
        # descriptions: Markdown to append, as { group_metadata => { test id or :group => text } }.
        def generate(ig_metadata, base_output_dir, descriptions = {})
          # A kit subclass may keep a three-argument initialize, so descriptions are passed only when there are some.
          added = descriptions.empty? ? [] : [descriptions]
          ig_metadata.ordered_groups
                     .compact
                     .reject do |group|
                       Registry.get(:config_keeper).exclude_resource?(group.profile_url, group.resource)
                     end
                     .each { |group| new(group, base_output_dir, ig_metadata, *added).generate }
        end
      end

      attr_accessor :group_metadata, :base_output_dir, :ig_metadata, :descriptions

      self.template_type = TEMPLATE_TYPES[:GROUP]

      def initialize(group_metadata, base_output_dir, ig_metadata, descriptions = {})
        self.group_metadata = group_metadata
        self.base_output_dir = base_output_dir
        self.ig_metadata = ig_metadata
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

      # The built-in description, then a blank line and any text added for the group.
      def description
        added = added_description(:group)
        added ? "#{built_in_description}\n#{added}\n" : built_in_description
      end

      # The Markdown added to the test, or nil. The template appends it to the test's own description in a
      # `test from:` block, so a test without added text keeps a plain `test from:` line.
      def test_description(test_id)
        added_description(test_id.to_s)
      end

      private

      # Added text is plain Markdown. The group template puts it inside a %( ... ) literal, where a backslash,
      # a parenthesis or #{ would break the file, so it is escaped here.
      def added_description(key)
        descriptions.dig(group_metadata, key)&.gsub(/[\\()]|#[{@$]/) { |match| "\\#{match}" }
      end

      def built_in_description
        Helpers.get_group_description_text(title, resource_type, profile_name, group_metadata.version, profile_url,
                                           required_searches, search_param_name_string, search_validation_resource_type, resource_type)
      end
    end
  end
end
