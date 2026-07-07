# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "basic_test_generator"
require_relative "../utils/registry"

module InfernoSuiteGenerator
  class Generator
    # Generator that creates tests to validate reference resolution in FHIR resources.
    # It generates tests to verify that references marked as MustSupport can be properly
    # resolved to their target resources. This includes checking that referenced
    # resources exist and are accessible via the FHIR server's RESTful API.
    class ReferenceResolutionTestGenerator < BasicTestGenerator
      class << self
        def generate(ig_metadata, base_output_dir)
          ig_metadata.groups.each do |group|
            next if Registry.get(:config_keeper).exclude_resource?(group.profile_url, group.resource)

            new(group, base_output_dir, ig_metadata).generate
          end
        end
      end

      attr_reader :config

      self.template_type = TEMPLATE_TYPES[:REFERENCE_RESOLUTION]

      def initialize(group_metadata, base_output_dir, ig_metadata)
        super
        @config = Registry.get(:config_keeper)
      end

      def resource_collection_string
        "scratch_resources[:all]"
      end

      def must_support_references
        group_metadata.must_supports[:elements]
                      .select { |element| element[:types]&.include?("Reference") }
      end

      def title
        config.title
      end

      def must_support_reference_list_string
        must_support_references
          .map { |element| "#{" " * 8}* #{resource_type}.#{element[:path]}" }
          .uniq
          .sort
          .join("\n")
      end

      def readable_resource_types
        ig_metadata.groups
                   .select { |group| group.interactions.any? { |interaction| interaction[:code] == "read" } }
                   .map(&:resource)
                   .uniq
                   .sort
      end

      def readable_resource_types_string
        readable_resource_types.map { |rt| "'#{rt}'" }.join(", ")
      end

      def rewrite_profile_url_hash
        config.rewrite_profile_url
      end

      def generate
        return if must_support_references.empty?

        FileUtils.mkdir_p(output_file_directory)
        File.write(output_file_name, output)

        group_metadata.add_test(
          id: test_id,
          file_name: base_output_file_name
        )
      end
    end
  end
end
