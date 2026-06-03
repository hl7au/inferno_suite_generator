# frozen_string_literal: true

module InfernoSuiteGenerator
  class MSChecker
    # Slice-related Must Support checks. Mixed into MSChecker.
    # rubocop:disable Metrics/ModuleLength
    module Slices
      def slices_present_statuses(resources = [], all_present: false)
        must_support_slices.map do |slice|
          build_slice_status(slice, resources, all_present:)
        end
      end

      private

      def build_slice_status(slice, resources, all_present: false)
        path = slice[:path]
        {
          definition: slice,
          path:,
          mandatory: mandatory_elements_clean.include?(path),
          present: slices_present?(resources, slice, all_present:)
        }
      end

      def slices_present?(resources, slice, all_present: false)
        if all_present
          resources.all? { |resource| must_support_slice_present?(resource, slice) }
        else
          resources.any? { |resource| must_support_slice_present?(resource, slice) }
        end
      end

      def must_support_slice_present?(resource, slice)
        path = slice[:path] # .delete_suffix('[x]')
        find_slice(resource, path, slice[:discriminator]).present?
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength
      def find_slice(resource, path, discriminator)
        find_a_value_at(resource, path) do |element|
          case discriminator[:type]
          when "patternCodeableConcept"
            coding_path = discriminator[:path].present? ? "#{discriminator[:path]}.coding" : "coding"
            find_a_value_at(element, coding_path) do |coding|
              coding.code == discriminator[:code] && coding.system == discriminator[:system]
            end
          when "patternCoding"
            coding_path = discriminator[:path].present? ? discriminator[:path] : ""
            find_a_value_at(element, coding_path) do |coding|
              coding.code == discriminator[:code] && coding.system == discriminator[:system]
            end
          when "patternIdentifier"
            find_a_value_at(element, discriminator[:path]) { |identifier| identifier.system == discriminator[:system] }
          when "value"
            values = discriminator[:values].map { |value| value.merge(path: value[:path].split(".")) }
            find_slice_by_values(element, values)
          when "type"
            case discriminator[:code]
            when "Date"
              date_like_slice?(element, "Date")
            when "DateTime"
              date_like_slice?(element, "DateTime")
            when "String"
              element.is_a? String
            else
              code = discriminator[:code].to_s
              next false unless defined?(FHIR) && FHIR.const_defined?(code)

              element.is_a? FHIR.const_get(code)
            end
          when "requiredBinding"
            coding_path = discriminator[:path].present? ? "#{discriminator[:path]}.coding" : "coding"
            find_a_value_at(element, coding_path) { |coding| discriminator[:values].include?(coding.code) }
          end
        end
      rescue StandardError => e
        error_message = [
          "Error finding slice for the resource #{resource.class.name}",
          "with path #{path} and discriminator #{discriminator}.",
          "Got error #{e.message}"
        ].join(" ")
        raise error_message
      end

      def find_slice_by_values(element, value_definitions)
        value_definitions = value_definitions.map { |vd| vd_merge_path(vd) }
        path_prefixes = value_definitions.map { |value_definition| value_definition[:path].first }.uniq
        Array.wrap(element).find do |el|
          path_prefixes.all? do |path_prefix|
            value_definitions_for_path =
              value_definitions
              .select { |value_definition| value_definition[:path].first == path_prefix }
              .each { |value_definition| value_definition[:path].shift }

            coding_prefixes = %w[code system display]
            search_path = if el.respond_to?(:coding) && !el.respond_to?(path_prefix.to_sym) &&
                             coding_prefixes.include?(path_prefix)
                            "coding.#{path_prefix}"
                          else
                            path_prefix
                          end

            find_a_value_at(el, search_path) do |el_found|
              child_element_value_definitions, current_element_value_definitions =
                value_definitions_for_path.partition { |value_definition| value_definition[:path].present? }

              current_element_values_match =
                current_element_value_definitions
                .all? do |value_definition|
                  expected = value_definition[:value]
                  if expected.is_a?(Array)
                    expected.any?(el_found)
                  else
                    expected == el_found
                  end
                end

              child_element_values_match =
                if child_element_value_definitions.present?
                  find_slice_by_values(el_found, child_element_value_definitions)
                else
                  true
                end

              current_element_values_match && child_element_values_match
            end
          end
        end
      end

      def must_support_slices
        prepare_uscdi_ms(:slices)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
