# frozen_string_literal: true

module InfernoSuiteGenerator
  module FHIRResourceNavigation
    DAR_EXTENSION_URL = "http://hl7.org/fhir/StructureDefinition/data-absent-reason"

    def resolve_path(elements, path, include_dar: false, metadata: nil)
      elements = Array.wrap(elements)
      return elements if path.blank?

      paths = path.split(/(?<!hl7)\./)
      segment = paths.first
      remaining_path = paths.drop(1).join(".")

      elements.flat_map do |element|
        child = get_next_value(element, segment, include_dar:, metadata:)
        resolve_path(child, remaining_path, include_dar:, metadata:)
      end.compact
    end

    def is_extension?(str)
      !!str.match(%r{extension\('https?://[^\s]+?\)\.value})
    end

    def get_extension_url(str)
      match = str.match(/extension\('([^']+)'\)\.value/)
      match ? match[1] : nil
    end

    def get_value_from_extension(element, extension_url)
      extension_elements = element.extension.filter { |ext| ext.url == extension_url }
      return nil unless extension_elements.length.positive?

      extension_element = extension_elements.first
      case extension_url
      when "http://hl7.org.au/fhir/StructureDefinition/indigenous-status"
        extension_element.valueCoding
      when "http://hl7.org/fhir/StructureDefinition/individual-genderIdentity"
        extension_element.extension.first.valueCodeableConcept
      else
        extension_element.valueCoding
      end
    end

    def find_a_value_at(element, path, include_dar: false, metadata: nil, &block)
      return nil if element.nil?

      return get_value_from_extension(element, get_extension_url(path)) if is_extension?(path)

      elements = Array.wrap(element)
      if path.empty?
        unless include_dar
          elements = elements.reject do |el|
            el.respond_to?(:extension) && el.extension.any? { |ext| ext.url == DAR_EXTENSION_URL }
          end
        end

        return elements.find(&block) if block_given?

        return elements.first
      end

      path_segments = path.split(/(?<!hl7)\./)

      segment = path_segments.shift.delete_suffix("[x]").gsub(/^class$/, "local_class").gsub("[x]:", ":").to_sym
      no_elements_present =
        elements.none? do |element|
          child = get_next_value(element, segment, include_dar:, metadata:)
          child.present? || child == false
        end
      return nil if no_elements_present

      remaining_path = path_segments.join(".")
      elements.each do |element|
        child = get_next_value(element, segment, include_dar:, metadata:)
        element_found =
          if block_given?
            find_a_value_at(child, remaining_path, include_dar:, metadata:, &block)
          else
            find_a_value_at(child, remaining_path, include_dar:, metadata:)
          end
        return element_found if element_found.present? || element_found == false
      end

      nil
    end

    def get_next_value(element, property, include_dar: false, metadata: nil)
      extension_url = property[/(?<=where\(url=').*(?='\))/]
      if extension_url.present?
        return nil unless element.respond_to?(:url)

        element.url == extension_url ? element : nil
      elsif property.to_s.include?(":") && !property.to_s.include?("url")
        find_slice_via_discriminator(element, property, metadata:)
      else
        local_name = local_field_name(property)
        return nil unless element.respond_to?(local_name)

        value = element.send(local_name)
        primitive_value = include_dar ? primitive_type_value_for(element, property, value) : nil
        primitive_value.nil? ? value : primitive_value
      end
    end

    def primitive_type_value_for(element, property, value)
      return nil unless element.respond_to?(:source_hash)

      source_value = element.source_hash["_#{property}"]
      return nil unless source_value.present?

      primitive = build_primitive_type(source_value)
      primitive.value = value if primitive.respond_to?(:value=)
      primitive
    end

    def build_primitive_type(source_value)
      if defined?(Inferno::DSL::PrimitiveType)
        Inferno::DSL::PrimitiveType.new(source_value)
      else
        PrimitiveTypeFallback.new(source_value)
      end
    end

    def local_field_name(field_name)
      %w[method class].include?(field_name.to_s) ? "local_#{field_name}" : field_name
    end

    class PrimitiveTypeFallback
      attr_accessor :value
      attr_reader :extension

      def initialize(source_hash)
        @extension = Array(source_hash["extension"]).map do |ext|
          ext.respond_to?(:url) ? ext : ExtensionFallback.new(ext["url"])
        end
      end
    end

    class ExtensionFallback
      attr_reader :url

      def initialize(url)
        @url = url
      end
    end

    def find_slice_via_discriminator(element, property, metadata: nil)
      return nil unless metadata.present?

      element_name = property.to_s.split(":")[0].gsub(/^class$/, "local_class")
      slice_name = property.to_s.split(":")[1].gsub(/^class$/, "local_class")
      slice_configs = metadata.must_supports&.[](:slices)
      return nil unless slice_configs

      slice_by_name = slice_configs.find { |slice| slice[:slice_name] == slice_name }
      return nil unless slice_by_name

      discriminator = slice_by_name[:discriminator]
      return nil unless discriminator

      return nil unless element.respond_to?(element_name.to_sym)

      slices = Array.wrap(element.send(element_name))
      slices.find { |slice| slice_matches_discriminator?(slice, discriminator, metadata:) }
    end

    def slice_matches_discriminator?(slice, discriminator, metadata: nil)
      case discriminator[:type]
      when "patternCodeableConcept"
        slice_value =
          if discriminator[:path].present?
            path = discriminator[:path].to_s
            return false unless slice.respond_to?(path.to_sym)

            nested = slice.send(path.to_sym)
            return false unless nested.respond_to?(:coding)

            nested.coding
          else
            return false unless slice.respond_to?(:coding)

            slice.coding
          end
        slice_value.any? { |coding| coding.code == discriminator[:code] && coding.system == discriminator[:system] }
      when "patternCoding"
        slice_value =
          if discriminator[:path].present?
            path = discriminator[:path].to_s
            return false unless slice.respond_to?(path.to_sym)

            slice.send(path.to_sym)
          else
            slice
          end
        return false unless slice_value.respond_to?(:code) && slice_value.respond_to?(:system)

        slice_value.code == discriminator[:code] && slice_value.system == discriminator[:system]
      when "patternIdentifier"
        return false unless slice.respond_to?(:identifier)
        return false unless slice.identifier.respond_to?(:system)

        slice.identifier.system == discriminator[:system]
      when "value"
        values = discriminator[:values].map { |value| value.merge(path: value[:path].split(".")) }
        verify_slice_by_values(slice, values, metadata:)
      when "type"
        case discriminator[:code]
        when "Date"
          date_like_slice?(slice, "Date")
        when "DateTime"
          date_like_slice?(slice, "DateTime")
        when "String"
          slice.is_a? String
        else
          code = discriminator[:code].to_s
          return false unless defined?(FHIR) && FHIR.const_defined?(code)

          slice.is_a? FHIR.const_get(code)
        end
      when "requiredBinding"
        binding_coding =
          if discriminator[:path].present?
            path = discriminator[:path].to_s
            return false unless slice.respond_to?(path.to_sym)

            nested = slice.send(path.to_sym)
            return false unless nested.respond_to?(:coding)

            nested.coding
          else
            return false unless slice.respond_to?(:coding)

            slice.coding
          end
        return false unless binding_coding.respond_to?(:any?)

        binding_coding.any? { |coding| discriminator[:values].include?(coding.code) }
      else
        false
      end
    end

    # Checks if a slice matches a Date or DateTime type by examining its type and attempting to parse string values
    # @param slice [Object] The slice to check
    # @param value_type [String] Either "Date" or "DateTime" to determine the type to check for
    # @return [Boolean] Returns true if the slice matches the specified date/time type, false otherwise
    def date_like_slice?(slice, value_type)
      if value_type == "Date" ? slice.is_a?(Date) : (slice.is_a?(DateTime) || slice.is_a?(Time))
        true
      else
        value = get_slice_value(slice)
        value.present? ? parse_date(value, value_type) : false
      end
    end

    # Gets the string value from a slice object
    # @param slice [Object] The slice to extract the value from
    # @return [String, nil] The string value of the slice, or nil if no value could be extracted
    def get_slice_value(slice)
      if slice.is_a?(String)
        slice
      elsif slice.respond_to?(:value) && slice.value.is_a?(String)
        slice.value
      end
    end

    # Attempts to parse a string value as either a Date or DateTime
    # @param value [String] The string value to parse
    # @param value_type [String] Either "Date" or "DateTime" to determine how to parse
    # @return [Boolean] Returns true if parsing was successful, false otherwise
    def parse_date(value, value_type)
      value_type == "Date" ? !Date.parse(value).nil? : !DateTime.parse(value).nil?
    end

    # Creates a duplicate of the value_definition hash with a deep copy of the :path array.
    # This prevents unintended mutations of the original :path array in the value_definition.
    def vd_merge_path(value_definition)
      value_definition.merge(path: value_definition[:path].dup)
    end

    def verify_slice_by_values(element, value_definitions, metadata: nil)
      value_definitions = value_definitions.map { |vd| vd_merge_path(vd) }
      path_prefixes = value_definitions.map { |value_definition| value_definition[:path].first }.uniq
      path_prefixes.all? do |path_prefix|
        value_definitions_for_path =
          value_definitions
          .select { |value_definition| value_definition[:path].first == path_prefix }
          .each { |value_definition| value_definition[:path].shift }

        search_path = if element.respond_to?(:coding) && !element.respond_to?(path_prefix.to_sym) && %w[code system
                                                                                                        display].include?(path_prefix)
                        "coding.#{path_prefix}"
                      else
                        path_prefix
                      end

        find_a_value_at(element, search_path, metadata:) do |el_found|
          child_element_value_definitions, current_element_value_definitions =
            value_definitions_for_path.partition { |value_definition| value_definition[:path].present? }

          current_element_values_match =
            current_element_value_definitions
            .all? { |value_definition| value_definition[:value] == el_found }

          child_element_values_match =
            if child_element_value_definitions.present?
              verify_slice_by_values(el_found, child_element_value_definitions, metadata:)
            else
              true
            end
          current_element_values_match && child_element_values_match
        end
      end
    end
  end
end
