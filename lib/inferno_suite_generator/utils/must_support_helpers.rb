# frozen_string_literal: true

module InfernoSuiteGenerator
  # The MustSupportHelpers module provides helper methods for must-support tests
  module MustSupportHelpers
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

    def build_element_status_text(element_status)
      is_mandatory = element_status[:mandatory]
      missing_icon = is_mandatory ? ERROR_ICON : WARNING_ICON
      missing_text = "#{missing_icon} Missing"
      populated_text = "#{SUCCESS_ICON} Populated"
      element_status_text = element_status[:present] ? populated_text : missing_text
      default_message = "#{element_status_text}: #{element_status[:path]}"
      is_mandatory ? "#{default_message} (M)" : default_message
    end

    def report_profile_elements_status(profile_metadata, resources_to_check)
      elements_statuses = elements_present_statuses(profile_metadata, resources_to_check)
      msg_level = calculate_elements_status_message_level(elements_statuses)

      {
        msg_level:,
        message: build_report_message(profile_metadata, elements_statuses).join("\n\n")
      }
    end

    def message_with_details(elements_statuses)
      status = calculate_elements_status_message_level(elements_statuses)

      return MANDATORY_ERROR_MS_MESSAGE if status == "error"
      return OPTIONAL_MS_WARNING_MESSAGE if status == "warning"

      MS_OKAY_MESSAGE
    end

    def build_report_message(profile_metadata, elements_statuses)
      [
        msg_line("Profile", "#{profile_metadata.resource} — #{profile_metadata.profile_url}"),
        msg_line("Message", message_with_details(elements_statuses)),
        "List of Must Support elements populated or missing",
        elements_statuses.map { |element_status| build_element_status_text(element_status) }
      ].flatten
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

    def calculate_elements_status_message_level(elements_statuses)
      return "error" if failed_status(elements_statuses)
      return "warning" if warning_status(elements_statuses)

      "info"
    end
  end
end
