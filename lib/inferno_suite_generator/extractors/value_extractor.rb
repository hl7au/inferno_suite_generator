# frozen_string_literal: true

require_relative "../core/fhirpath_expressions"

module InfernoSuiteGenerator
  class Generator
    class ValueExactor
      attr_accessor :ig_resources, :resource, :profile_elements

      def initialize(ig_resources, resource, profile_elements)
        self.ig_resources = ig_resources
        self.resource = resource
        self.profile_elements = profile_elements
      end

      def values_from_required_binding(profile_element)
        return [] unless profile_element&.max == "*"

        profile_elements
          .select do |element|
            element.path == profile_element.path && element.binding&.strength == "required"
          end
          .map { |element| values_from_value_set_binding(element) }
          .flatten.compact
      end

      def values_from_fixed_codes(profile_element, type)
        return [] unless type == "CodeableConcept"

        profile_elements
          .select do |element|
            element.path == "#{profile_element.path}.coding.code" && element.fixedCode.present?
          end
          .map(&:fixedCode)
      end

      def values_from_pattern_coding(profile_element, type)
        return [] unless type == "CodeableConcept"

        profile_elements
          .select do |element|
            element.path == "#{profile_element.path}.coding" && element.patternCoding.present?
          end
          .map { |element| element.patternCoding.code }
      end

      def values_from_pattern_codeable_concept(profile_element, type)
        return [] unless type == "CodeableConcept"

        profile_elements
          .select do |element|
            element.path == profile_element.path && element.patternCodeableConcept.present? && element.min.positive?
          end
          .map { |element| element.patternCodeableConcept.coding.first.code }
      end

      def value_set(the_element)
        ig_resources.value_set_by_url(the_element&.binding&.valueSet)
      end

      def codes_from_value_set(value_set)
        return [] if value_set.nil?

        inline_codes = FhirpathExpressions.value_set_inline_concept_codes.call(value_set)

        code_system_codes = FhirpathExpressions.value_set_lookup_system_urls.call(value_set).flat_map do |system_url|
          code_system = ig_resources.code_system_by_url(system_url)
          code_system ? FhirpathExpressions.code_system_concept_codes.call(code_system) : []
        end

        nested_codes = FhirpathExpressions.value_set_included_value_set_urls.call(value_set).flat_map do |nested_url|
          codes_from_value_set(ig_resources.value_set_by_url(nested_url))
        end

        inline_codes + code_system_codes + nested_codes
      end

      def values_from_value_set_binding(the_element)
        codes_from_value_set(value_set(the_element)).uniq
      end

      def fhir_metadata(current_path)
        FHIR.const_get(resource)::METADATA[current_path]
      end

      def values_from_resource_metadata(paths)
        values = []

        paths.each do |current_path|
          current_metadata = fhir_metadata(current_path)

          values += current_metadata["valid_codes"].values.flatten if current_metadata&.dig("valid_codes").present?
        end

        values
      end
    end
  end
end
