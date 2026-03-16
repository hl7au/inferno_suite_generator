# frozen_string_literal: true

module InfernoSuiteGenerator
  module CreateTest
    # Helpers for creating tests: updating FHIR resources with references from IG metadata.
    # Builds path/value pairs from reference config and applies them via {SetByPath}.
    module CreateTestHelpers
      # Represents a FHIR reference path, with logic to transform [x] polymorphic paths.
      #
      # @example
      #   ReferencePath.new('subject[x]').to_fhirpath_string #=> 'subjectReference'
      class ReferencePath
        # @return [String] the original path (potentially with [x] for FHIR polymorphics)
        attr_reader :path

        # Initializes a new ReferencePath.
        #
        # @param path [String] The FHIR path string (may contain '[x]')
        def initialize(path)
          @path = path
        end

        # Converts a FHIR path string with '[x]' polymorphic notation to the Reference type.
        #
        # @return [String] The FHIR path with '[x]' replaced by 'Reference' if applicable,
        #   otherwise returns the original path.
        def to_fhirpath_string
          @path.include?("[x]") ? @path.gsub("[x]", "Reference") : @path
        end
      end

      # Deep-copies the resource, sets reference paths from IG metadata, and returns a new FHIR resource.
      #
      # @param resource [FHIR::Model] A FHIR resource instance
      # @return [FHIR::Model] A new FHIR resource with references filled from metadata.references
      def update_resource_by_references(resource)
        resource_data = deep_copy_hash(resource.to_hash)
        paths_and_values = build_reference_paths_and_values(metadata.references, resource)
        resource_data = SetByPath.multi_set_by_path(resource_data, paths_and_values)
        FHIR.from_contents(resource_data.to_json)
      end

      # Builds an array of [path, value, datatype] tuples for paths present in the resource.
      #
      # @param references_ig_config [Array<Hash>] IG reference config (each hash has :path, :resource_types)
      # @param resource [FHIR::Model] A FHIR resource instance
      # @return [Array<Array>] Array of [path, reference_hash, datatype] for {SetByPath.multi_set_by_path}
      def build_reference_paths_and_values(references_ig_config, resource)
        prepare_paths_to_set_references_for_resource(references_ig_config, resource).filter_map do |path|
          reference_pair_for_path(path, references_ig_config)
        end
      end

      # Returns unique reference paths from IG config that are present in the resource.
      #
      # @param references_ig_config [Array<Hash>] IG reference config (each hash has :path)
      # @param resource [FHIR::Model] A FHIR resource instance
      # @return [Array<String>] Unique FHIRPath-like paths present in the resource
      def prepare_paths_to_set_references_for_resource(references_ig_config, resource)
        references_ig_config.map { |ref| ref[:path] }.uniq.filter { |path| path_present_in_resource?(path, resource) }
      end

      # Checks whether the reference path exists in the resource (FHIRPath evaluation).
      #
      # @param path [String] FHIRPath-like path (may contain +[x]+ for choice types)
      # @param resource [FHIR::Model] A FHIR resource instance
      # @return [Boolean] true if the path is present and has a value, false otherwise
      def path_present_in_resource?(path, resource)
        fhirpath_string = ReferencePath.new(path).to_fhirpath_string
        evaluate_fhirpath(resource:, path: fhirpath_string).any?
      end

      # Finds the reference config for a path and builds a [path, value, datatype] tuple if applicable.
      #
      # @param path [String] FHIRPath-like path
      # @param references_ig_config [Array<Hash>] IG reference config (each hash has :path, :resource_types)
      # @return [Array, nil] [path, reference_hash, datatype] or nil if no matching reference or no resource_types
      def reference_pair_for_path(path, references_ig_config)
        current_reference = references_ig_config.find { |ref| ref[:path] == path }
        return unless current_reference && current_reference[:resource_types]&.any?

        pair_from_reference(current_reference, path)
      end

      # Builds a single [path, reference_hash, datatype] tuple from a reference config entry.
      #
      # @param ref [Hash] Reference config entry with :resource_types
      # @param path [String] FHIRPath-like path (used for datatype extraction when path has +[x]+)
      # @return [Array, nil] [path, { "reference" => "ResourceType/id" }, datatype] or nil if no stored reference
      def pair_from_reference(ref, path)
        resource_type = ref[:resource_types].first
        resource_id = references_keeper.references_for_resource_type(resource_type).first
        return unless resource_id

        [path, { "reference" => "#{resource_type}/#{resource_id}" }, SetByPath.extract_datatype_from_path(path)]
      end
    end
  end
end
