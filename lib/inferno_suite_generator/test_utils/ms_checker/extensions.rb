# frozen_string_literal: true

require_relative "../../utils/helpers"

module InfernoSuiteGenerator
  class MSChecker
    # Extension-related Must Support checks. Mixed into MSChecker.
    module Extensions
      def extensions_present_statuses(resources = [], all_present: false)
        must_support_extensions.map do |extension_definition|
          build_extension_status(extension_definition, resources, all_present:)
        end
      end

      private

      def build_extension_status(extension_definition, resources, all_present: false)
        {
          definition: extension_definition,
          url: extension_definition[:url],
          present: extensions_present?(resources, extension_definition, all_present:)
        }
      end

      def extensions_present?(resources, extension_definition, all_present: false)
        if all_present
          resources.all? { |resource| extension_present?(resource, extension_definition) }
        else
          resources.any? { |resource| extension_present?(resource, extension_definition) }
        end
      end

      def extension_present?(resource, extension_definition)
        resource_extensions_url_arr = Helpers.extract_extensions_from_resource(resource).map { |ext| ext["url"] }
        resource_extensions_url_arr.include? extension_definition[:url]
      end

      def must_support_extensions
        prepare_uscdi_ms(:extensions)
      end
    end
  end
end
