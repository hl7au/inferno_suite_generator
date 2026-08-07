# frozen_string_literal: true

require_relative "../core/ig_metadata"
require_relative "group_metadata_extractor"
require_relative "../utils/registry"

module InfernoSuiteGenerator
  class Generator
    class IGMetadataExtractor
      attr_accessor :ig_resources, :metadata, :config_keeper

      def initialize(ig_resources)
        self.ig_resources = ig_resources
        self.metadata = IGMetadata.new
        self.config_keeper = Registry.get(:config_keeper)
      end

      def extract
        add_metadata_from_ig
        add_metadata_from_resources
        metadata
      end

      def add_metadata_from_ig
        metadata.ig_version = "v#{config_keeper.version}"
        metadata.ig_id = config_keeper.id
        metadata.ig_title = config_keeper.title
        metadata.ig_module_name_prefix = config_keeper.module_name_prefix
        metadata.ig_test_id_prefix = config_keeper.test_id_prefix
      end

      def resources_in_capability_statement
        ig_resources.cs_resources
      end

      def extract_group_metadata(resource, profile, metadata, ig_resources)
        begin
          GroupMetadataExtractor.new(resource, profile, metadata, ig_resources).group_metadata
        rescue StandardError => e
          warn "Error extracting metadata for profile #{profile} of resource #{resource.type}: #{e.message}"
          nil
        end
      end

      def extract_resource_profiles(cs_resource)
        all_profiles = [*cs_resource.supportedProfile, cs_resource.profile].compact.uniq.map { |p| p.split("|").first }.uniq
        all_profiles.reject { |profile| config_keeper.skip_metadata_extraction?(profile, cs_resource.type) }.compact
      end

      def extract_metadata_for_cs_resource(cs_resource)
        extract_resource_profiles(cs_resource).map do |profile|
          extract_group_metadata(cs_resource, profile, metadata, ig_resources)
        end.compact
      end

      def add_metadata_from_resources
        metadata.groups = resources_in_capability_statement.flat_map(&method(:extract_metadata_for_cs_resource)).compact
        metadata.postprocess_groups(ig_resources)
      end
    end
  end
end