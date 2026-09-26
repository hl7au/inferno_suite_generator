# frozen_string_literal: true

module InfernoSuiteGenerator
  # Extend an Inferno::DSL::FHIRResourceValidation::Validator instance with this module
  # to remap validator message severities via regex rules
  module ValidationMessageOverrides
    SEVERITY_TO_LEVEL = { "error" => "ERROR", "warning" => "WARNING", "info" => "INFORMATION" }.freeze

    def message_overrides(rules = nil)
      @message_overrides = rules.map { |rule| compile_override(rule) } if rules
      @message_overrides || []
    end

    def mark_issues_for_filtering(issues)
      apply_message_overrides(issues)
      super
    end

    private

    def apply_message_overrides(issues)
      issues.each do |issue|
        rule = message_overrides.find { |candidate| override_matches?(candidate, issue) }
        override_severity(issue, rule[:to]) if rule
        apply_message_overrides(issue.slice_info) if issue.slice_info.any?
      end
    end

    def override_matches?(rule, issue)
      severity_matches?(rule, issue) &&
        message_id_matches?(rule, issue) &&
        location_matches?(rule, issue) &&
        rule[:pattern].match?(issue.message)
    end

    def severity_matches?(rule, issue)
      rule[:from].nil? || rule[:from].include?(issue.severity)
    end

    def message_id_matches?(rule, issue)
      rule[:message_id].nil? || rule[:message_id] == issue.raw_issue["messageId"]
    end

    def location_matches?(rule, issue)
      rule[:location].nil? || rule[:location].match?(issue.location.to_s)
    end

    # Rewrites raw_issue["level"] rather than forcing @severity, so the validator debug
    # log and validator_response_details also show the new level.
    def override_severity(issue, severity)
      issue.raw_issue = issue.raw_issue.merge(
        "level" => SEVERITY_TO_LEVEL.fetch(severity),
        "originalLevel" => issue.raw_issue["originalLevel"] || issue.raw_issue["level"]
      )
      issue.remove_instance_variable(:@severity) if issue.instance_variable_defined?(:@severity)
    end

    def compile_override(rule)
      rule = rule.transform_keys(&:to_s)
      {
        pattern: Regexp.new(rule.fetch("pattern")),
        location: rule["location"] && Regexp.new(rule["location"]),
        message_id: rule["message_id"],
        from: rule["from"] && Array(rule["from"]).map { |severity| severity.to_s.downcase },
        to: rule.fetch("to").to_s.downcase
      }
    end
  end
end
