# frozen_string_literal: true

module InfernoSuiteGenerator
  class Generator
    # Represents demo data for Inferno Suite Generator testing scenarios.
    #
    # This class serves as a data container for managing test resources, including
    # resource IDs, full resource bodies, and partial resource bodies for PATCH operations.
    # It provides a structured way to organize and access demo data used in testing workflows.
    class IGDemodata
      attr_accessor :resource_ids, :resource_body_list, :patch_body_list, :resource_types_to_search

      def initialize(data = nil)
        return unless data

        @resource_ids = extract_value(data, "resource_ids", :resource_ids)
        @resource_body_list = extract_value(data, "resource_body_list", :resource_body_list)
        @patch_body_list = extract_value(data, "patch_body_list", :patch_body_list)
        @resource_types_to_search = extract_value(data, "resource_types_to_search", :resource_types_to_search)
      end

      def to_hash
        {
          resource_ids:,
          resource_body_list:,
          patch_body_list:,
          resource_types_to_search:
        }
      end

      private

      def extract_value(data, string_key, symbol_key)
        return nil unless data.is_a?(Hash)

        data[string_key] || data[symbol_key]
      end
    end
  end
end
