# frozen_string_literal: true

require_relative "../utils/fhir_resource_navigation"
require_relative "ms_checker/extensions"
require_relative "ms_checker/slices"

module InfernoSuiteGenerator
  # Evaluates Must Support coverage for a test group.
  #
  # Features:
  # - Builds per-element presence statuses across provided resources.
  # - Distinguishes mandatory-missing elements (error) from optional-missing
  #   elements (warning).
  # - Produces a human-readable report with profile context and per-element
  #   populated/missing indicators.
  # - Supports configurable top-level status messages through `@config` keys:
  #   `mandatory_error_message`, `optional_warning_message`, and
  #   `okay_message`.
  class MSChecker # rubocop:disable Metrics/ClassLength
    include FHIRResourceNavigation
    include Extensions
    include Slices

    MANDATORY_ERROR_MS_MESSAGE = "At least one mandatory Must Support elements is not populated."
    OPTIONAL_MS_WARNING_MESSAGE = [
      "At least one optional Must Support element is not populated. ",
      "Further testing with data containing the missing elements or clarification ",
      "the system does not ever know a value for the element is required."
    ].join.freeze
    MS_OKAY_MESSAGE = "All Must Support elements are populated."

    ERROR_ICON = "❌"
    WARNING_ICON = "⚠️"
    SUCCESS_ICON = "✅"

    def initialize(group_metadata, config = {})
      @metadata = group_metadata
      @config = config
    end

    def elements_present_statuses(resources = [], all_present: false)
      must_support_elements.map do |element_definition|
        build_element_status(element_definition, mandatory_elements_clean, resources, all_present:)
      end
    end

    def calculate_elements_status_message_level(elements_statuses)
      return "error" if failed_status(elements_statuses)
      return "warning" if warning_status(elements_statuses)

      "info"
    end

    def build_report_message(profile_metadata, elements_statuses)
      [
        message_with_details(elements_statuses),
        msg_line("Profile", "#{profile_metadata.resource} — #{profile_metadata.profile_url}"),
        "List of Must Support elements populated or missing",
        elements_statuses.map { |element_status| build_element_status_text(element_status) }
      ].flatten
    end

    private

    def mandatory_elements_clean
      @metadata.mandatory_elements.map do |element|
        element.gsub("#{@metadata.resource}.", "")
      end
    end

    def build_element_status(element_definition, mandatory_elements, resources, all_present: false)
      path = element_definition[:path]

      {
        definition: element_definition,
        path:,
        mandatory: mandatory_elements.include?(path),
        present: elements_present?(resources, element_definition, all_present:)
      }
    end

    def elements_present?(resources, element_definition, all_present: false)
      if all_present
        resources.all? { |resource| must_support_element_present?(element_definition, resource) }
      else
        resources.any? { |resource| must_support_element_present?(element_definition, resource) }
      end
    end

    def must_support_element_present?(element_definition, resource)
      path = element_definition[:path]
      value_found = value_found?(resource, path, element_definition)
      return true if value_found.present? || value_found == false

      dar_found?(resource, path)
    end

    def dar_found?(resource, path)
      find_a_value_at(resource, path, include_dar: true) do |value|
        value.respond_to?(:extension) &&
          value.extension.any? { |ext| ext.url == DAR_EXTENSION_URL }
      end.present? || primitive_dar_found?(resource, path)
    end

    def primitive_dar_found?(resource, path)
      primitive_paths_with_extensions(path).any? do |primitive_path|
        resolve_path([resource], primitive_path).any? { |ext| ext.url == DAR_EXTENSION_URL }
      end
    end

    def primitive_paths_with_extensions(path)
      path_segments = path.split(/(?<!hl7)\./)
      primitive_segment = path_segments.pop
      nested_primitive_path = [*path_segments, "_#{primitive_segment}", "extension"].join(".")

      ["#{path}.extension", nested_primitive_path].uniq
    end

    def must_support_elements
      prepare_uscdi_ms(:elements)
    end

    def prepare_uscdi_ms(metadata_key)
      return ms_exclude_usdi(metadata_key) if exclude_uscdi_only_test?

      @metadata.must_supports&.dig(metadata_key) || []
    end

    def exclude_uscdi_only_test?
      !!@config["exclude_uscdi_only_test"]
    end

    def ms_exclude_usdi(metadata_key)
      @metadata.must_supports&.dig(metadata_key)&.reject { |item| item[:uscdi_only] } || []
    end

    def value_found?(resource, path, element_definition)
      find_a_value_at(resource, path) do |value|
        value_without_extensions =
          value.respond_to?(:to_hash) ? value.to_hash.except("extension") : value

        (value_without_extensions.present? || value_without_extensions == false) &&
          (element_definition[:fixed_value].blank? || value == element_definition[:fixed_value])
      end
    end

    def message_with_details(elements_statuses)
      status = calculate_elements_status_message_level(elements_statuses)

      if status == "error"
        return ms_checker_config_getter(key: "mandatory_error_message",
                                        default: MANDATORY_ERROR_MS_MESSAGE)
      end

      if status == "warning"
        return ms_checker_config_getter(key: "optional_warning_message",
                                        default: OPTIONAL_MS_WARNING_MESSAGE)
      end

      ms_checker_config_getter(key: "okay_message", default: MS_OKAY_MESSAGE)
    end

    def ms_checker_config_getter(key:, default: nil)
      @config[key] || default
    end

    def msg_line(label, value)
      "**#{label}**: #{value}"
    end

    def result_has?(results, result_type)
      results.any?(result_type)
    end

    def results_eror?(results)
      result_has?(results, "error")
    end

    def results_warning?(results)
      result_has?(results, "warning")
    end

    def element_status_has?(element_status, present, mandatory)
      element_status[:present] == present && element_status[:mandatory] == mandatory
    end

    def optional_present?(element_status)
      element_status_has?(element_status, false, false)
    end

    def mandatory_present?(element_status)
      element_status_has?(element_status, false, true)
    end

    def failed_status(elements_statuses)
      elements_statuses.any? do |element_status|
        mandatory_present?(element_status)
      end
    end

    def warning_status(elements_statuses)
      elements_statuses.none? do |element_status|
        mandatory_present?(element_status)
      end && elements_statuses.any? do |element_status|
        optional_present?(element_status)
      end
    end

    def build_element_status_text(element_status)
      is_child = element_status[:path].include?(".")
      is_mandatory = element_status[:mandatory]
      missing_icon = is_mandatory ? ERROR_ICON : WARNING_ICON
      missing_text = "#{missing_icon} Missing"
      populated_text = "#{SUCCESS_ICON} Populated"
      element_status_text = element_status[:present] ? populated_text : missing_text
      default_message = "#{element_status_text}: #{element_status[:path]}"
      message_with_mandatory = is_mandatory ? "#{default_message} (M)" : default_message
      is_child ? "|- #{message_with_mandatory}" : message_with_mandatory
    end
  end
end
