# frozen_string_literal: true

require "fhir_models"
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
        add_config_metadata 
        add_groups_metadata
        metadata
      end

      def add_groups_metadata
        metadata.groups = resources_in_capability_statement.flat_map(&method(:extract_metadata_for_cs_resource)).compact
        metadata.groups = reorder_groups(metadata.groups)
        metadata.postprocess_groups(ig_resources)
      end

      private

      def reorder_groups(groups)
        order = config_keeper.groups_order
        return groups if order.blank?

        groups_by_profile_url = groups.group_by(&:profile_url)
        ordered_groups = order.flat_map { |profile_url| groups_by_profile_url.delete(profile_url) || [] }
        remaining_groups = groups_by_profile_url.values.flatten

        ordered_groups + remaining_groups
      end

      def add_config_metadata
        metadata.ig_version = "v#{config_keeper.version}"
        metadata.ig_id = config_keeper.id
        metadata.ig_title = config_keeper.title
        metadata.ig_module_name_prefix = config_keeper.module_name_prefix
        metadata.ig_test_id_prefix = config_keeper.test_id_prefix
      end

      def resources_in_capability_statement
        cs_resources = ig_resources.cs_resources
        return cs_resources if cs_resources.present?

        auto_detected_profile_resources
      end

      def auto_detected_profile_resources
        profiles = ig_resources.profile_structure_definitions

        if profiles.blank?
          warn "No CapabilityStatement found in the IG and no profile StructureDefinitions " \
               "(kind=resource, derivation=constraint) were found to build one from — no groups " \
               "will be generated."
          return []
        end

        profile_urls_by_resource_type(profiles).map do |resource_type, urls|
          FHIR::CapabilityStatement::Rest::Resource.new(
            "type" => resource_type,
            "supportedProfile" => urls
          )
        end
      end

      def profile_urls_by_resource_type(profiles)
        profiles.each_with_object({}) do |profile, grouped|
          (grouped[profile.type] ||= []) << profile.url
        end
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


    end
  end
end
