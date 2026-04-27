# frozen_string_literal: true

require_relative "../utils/fhir_resource_navigation"
require_relative "../utils/helpers"
require_relative "../utils/assert_helpers"
require_relative "../utils/filter_set"
require_relative "../utils/must_support_helpers"

module InfernoSuiteGenerator
  module MustSupportTest
    extend Forwardable
    include FHIRResourceNavigation
    include AssertHelpers
    include MustSupportHelpers

    def_delegators "self.class", :metadata

    def all_scratch_resources
      scratch_resources[:all]
    end

    def perform_must_support_test(resources)
      conditional_skip_with_msg resources.blank?, "No #{resource_type} resources were found"

      report_msg = report_profile_elements_status(metadata, resources)
      add_message(report_msg[:msg_level], report_msg[:message])

      missing_elements(resources, metadata)
      missing_slices(resources, metadata)
      missing_extensions(resources, metadata)

      handle_must_support_choices if metadata.must_supports[:choices].present?

      pass if (missing_elements + missing_slices + missing_extensions).empty?
      skip_with_msg "Could not find #{missing_must_support_strings.join(", ")} element(s) in the #{resources.length} " \
                    "provided #{resource_type} resource(s). To prevent this issue, please add the missing must support " \
                    "elements to at least one #{resource_type} resource on the server."
    end

    def handle_must_support_choices
      missing_elements.delete_if do |element|
        choices = metadata.must_supports[:choices].find { |choice| choice[:paths]&.include?(element[:path]) }
        is_any_choice_supported?(choices)
      end

      missing_extensions.delete_if do |extension|
        choices = metadata.must_supports[:choices].find { |choice| choice[:extension_ids]&.include?(extension[:id]) }
        is_any_choice_supported?(choices)
      end

      missing_slices.delete_if do |slice|
        choices = metadata.must_supports[:choices].find { |choice| choice[:slice_names]&.include?(slice[:name]) }
        is_any_choice_supported?(choices)
      end
    end

    def is_any_choice_supported?(choices)
      choices.present? &&
        (
          choices[:paths]&.any? { |path| missing_elements.none? { |element| element[:path] == path } } ||
          choices[:extension_ids]&.any? do |extension_id|
            missing_extensions.none? do |extension|
              extension[:id] == extension_id
            end
          end ||
          choices[:slice_names]&.any? { |slice_name| missing_slices.none? { |slice| slice[:name] == slice_name } }
        )
    end

    def missing_must_support_strings
      result = missing_elements.map { |element_definition| missing_element_string(element_definition) } +
               missing_slices.map { |slice_definition| slice_definition[:slice_id] } +
               missing_extensions.map { |extension_definition| extension_definition[:id] }

      result.map { |missing_element| "'#{missing_element}'" }
    end

    def missing_element_string(element_definition)
      if element_definition[:fixed_value].present?
        "#{element_definition[:path]}:#{element_definition[:fixed_value]}"
      else
        element_definition[:path]
      end
    end

    def exclude_uscdi_only_test?
      config.options[:exclude_uscdi_only_test] == true
    end

    def prepare_uscdi_ms(metadata_key, metadata = nil)
      if exclude_uscdi_only_test?
        metadata&.must_supports&.dig(metadata_key)&.reject { |item| item[:uscdi_only] } || []
      else
        metadata&.must_supports&.dig(metadata_key) || []
      end
    end

    def must_support_extensions(metadata = nil)
      prepare_uscdi_ms(:extensions, metadata)
    end

    def extension_present?(resource, extension_definition)
      resource_extensions_url_arr = Helpers.extract_extensions_from_resource(resource).map { |ext| ext["url"] }
      resource_extensions_url_arr.include? extension_definition[:url]
    end

    def extensions_present_statuses(metadata = nil, resources = [])
      must_support_extensions(metadata).map do |extension_definition|
        {
          definition: extension_definition,
          url: extension_definition[:url],
          present: resources.any? { |resource| extension_present?(resource, extension_definition) }
        }
      end
    end

    def miss_extensions(metadata = nil, resources = [])
      found_extensions = extensions_present_statuses(metadata, resources).select do |extension_status|
        !extension_status[:present]
      end
      found_extensions.map { |extension_status| extension_status[:definition] }
    end

    def missing_extensions(resources = [], metadata = nil)
      @missing_extensions ||= miss_extensions(metadata, resources)
      @missing_extensions
    end

    def must_support_elements(metadata = nil)
      prepare_uscdi_ms(:elements, metadata)
    end

    # Checks if a value is found at the given FHIRPath within a resource that satisfies the
    # must-support element definition, including fixed-value constraints if specified.
    # Ignores the 'extension' field when checking for presence.
    #
    # @param resource [Hash] the resource to inspect
    # @param path [String] the FHIRPath to the element
    # @param element_definition [Hash] definition hash, may include :fixed_value
    # @return [Object, nil] the value if found and matches constraints, otherwise nil
    def value_found?(resource, path, element_definition)
      find_a_value_at(resource, path) do |value|
        value_without_extensions =
          value.respond_to?(:to_hash) ? value.to_hash.except("extension") : value

        (value_without_extensions.present? || value_without_extensions == false) &&
          (element_definition[:fixed_value].blank? || value == element_definition[:fixed_value])
      end
    end

    # Checks whether the given must-support element is present in the resource.
    # Presence is determined by finding a value at the specified FHIRPath that satisfies
    # any fixed value constraints (if specified in the element definition).
    # Returns true if the value is present (including the special case of false values),
    # otherwise returns false.
    #
    # @param element_definition [Hash] The definition of the must-support element, including its FHIRPath and any fixed value.
    # @param resource [Hash] The FHIR resource to check for the element's presence.
    # @return [Boolean] True if the element is present in the resource, false otherwise.
    def must_support_element_present?(element_definition, resource)
      path = element_definition[:path]
      value_found = value_found?(resource, path, element_definition)
      value_found.present? || value_found == false
    end


    # Returns an array of hashes describing the presence status of each must-support element
    # in the provided resources. For each must-support element definition in the metadata,
    # checks all resources to see if any resource satisfies the must-support condition, and
    # records whether it is present.
    #
    # @param metadata [Hash, nil] Optional metadata containing must-support element definitions.
    # @param resources [Array<Hash>] Array of FHIR resources to check for element presence.
    # @return [Array<Hash>] Array of hashes, each with :path and :present keys.
    def elements_present_statuses(metadata = nil, resources = [])
      mandatory_elements = metadata.mandatory_elements.map { |element| element.gsub("#{metadata.resource}.", "") }
      must_support_elements(metadata).map do |element_definition|
        path = element_definition[:path]

        {
          definition: element_definition,
          path: path,
          mandatory: mandatory_elements.include?(path),
          present: resources.any? { |resource| must_support_element_present?(element_definition, resource) }
        }
      end
    end

    # Finds and returns all must-support elements that are missing from the provided resources.
    # This method filters the must-support elements based on the presence of matching values in the resources.
    #
    # @param metadata [Hash, nil] Optional metadata containing must-support element definitions.
    # @param resources [Array] Array of FHIR resources to check for presence of must-support elements.
    # @return [Array] Array of must-support elements that are missing from the resources.
    def miss_elements(metadata = nil, resources = [])
      found_elements = elements_present_statuses(metadata, resources).select do |element_status|
        !element_status[:present]
      end
      found_elements.map { |element_status| element_status[:definition] }
    end

    def missing_elements(resources = [], metadata = nil)
      @missing_elements ||= miss_elements(metadata, resources)
      @missing_elements
    end

    def must_support_slices(metadata = nil)
      prepare_uscdi_ms(:slices, metadata)
    end

    def must_support_slice_present?(resource, slice)
      path = slice[:path] # .delete_suffix('[x]')
      find_slice(resource, path, slice[:discriminator]).present?
    end

    def slices_present_statuses(metadata = nil, resources = [])
      must_support_slices(metadata).map do |slice|
        {
          definition: slice,
          path: slice[:path],
          present: resources.any? { |resource| must_support_slice_present?(resource, slice) }
        }
      end
    end

    def miss_slices(metadata = nil, resources = [])
      found_slices = slices_present_statuses(metadata, resources).select do |slice_status|
        !slice_status[:present]
      end
      found_slices.map { |slice_status| slice_status[:definition] }
    end

    def missing_slices(resources = [], metadata = nil)
      @missing_slices ||= miss_slices(metadata, resources)
      @missing_slices
    end

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
            element.is_a? FHIR.const_get(discriminator[:code])
          end
        when "requiredBinding"
          coding_path = discriminator[:path].present? ? "#{discriminator[:path]}.coding" : "coding"
          find_a_value_at(element, coding_path) { |coding| discriminator[:values].include?(coding.code) }
        end
      end
    rescue StandardError => e
      error_message = "Error finding slice for the resource #{resource.class.name} with path #{path} and discriminator #{discriminator}. Got error #{e.message}"
      raise error_message
    end

    def find_slice_by_values(element, value_definitions)
      path_prefixes = value_definitions.map { |value_definition| value_definition[:path].first }.uniq
      Array.wrap(element).find do |el|
        path_prefixes.all? do |path_prefix|
          value_definitions_for_path =
            value_definitions
            .select { |value_definition| value_definition[:path].first == path_prefix }
            .each { |value_definition| value_definition[:path].shift }

          search_path = if el.respond_to?(:coding) && !el.respond_to?(path_prefix.to_sym) && %w[code system
                                                                                                display].include?(path_prefix)
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
                  expected.any? { |v| v == el_found }
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
  end
end
