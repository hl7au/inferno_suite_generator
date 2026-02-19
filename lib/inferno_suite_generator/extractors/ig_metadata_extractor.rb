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

      def add_metadata_from_resources
        supported_profile_groups = resources_in_capability_statement.flat_map do |resource|
          resource.supportedProfile&.map do |supported_profile|
            supported_profile = supported_profile.split("|").first
            next if config_keeper.skip_metadata_extraction?(supported_profile, resource.type)
            begin
              GroupMetadataExtractor.new(resource, supported_profile, metadata, ig_resources).group_metadata
            rescue StandardError => e
              warn "Error extracting metadata for supported profile #{supported_profile} of resource #{resource.type}: #{e.message}"
              nil
            end
          end
        end.compact

        profile_groups = resources_in_capability_statement.flat_map do |resource|
          next unless resource.profile.present?
          next if config_keeper.skip_metadata_extraction?(resource.profile, resource.type)
          begin
            GroupMetadataExtractor.new(resource, resource.profile, metadata, ig_resources).group_metadata
          rescue StandardError => e
            warn "Error extracting metadata for profile #{resource.profile} of resource #{resource.type}: #{e.message}"
            nil
          end
        end.compact

        metadata.groups = supported_profile_groups + profile_groups

        metadata.postprocess_groups(ig_resources)
      end
    end
  end
end
