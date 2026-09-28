# frozen_string_literal: true

module InfernoSuiteGenerator
  # Extend an Inferno::DSL::FHIRResourceValidation::Validator instance with this module
  # to remap validator message severities via regex rules
  module ValidationMessageOverrides
    SEVERITY_TO_LEVEL = { "error" => "ERROR", "warning" => "WARNING", "info" => "INFORMATION" }.freeze
    SEVERITIES = SEVERITY_TO_LEVEL.keys.freeze
    RULE_KEYS = %w[pattern location message_id from to].freeze
    MATCH_ANYTHING = //

    # A class to keep config for override validator message level
    # :reek:TooManyInstanceVariables
    class Rule
      attr_reader :config

      def initialize(config)
        @config = config.transform_keys(&:to_s).slice(*RULE_KEYS)
        @pattern = Regexp.new(fetch_required("pattern"))
        @location = Regexp.new(@config["location"] || MATCH_ANYTHING)
        @message_id = @config["message_id"]
        @from = Array(@config["from"] || SEVERITIES).map { |severity| severity(severity, "from") }
        @to = severity(fetch_required("to"), "to")
      end

      def matches?(issue)
        @from.include?(issue.severity) &&
          message_id_matches?(issue.raw_issue["messageId"]) &&
          @location.match?(issue.location.to_s) &&
          @pattern.match?(issue.message)
      end

      # :reek:FeatureEnvy
      def apply(issue)
        raw_issue = issue.raw_issue
        issue.raw_issue = raw_issue.merge(
          "level" => SEVERITY_TO_LEVEL.fetch(@to),
          "originalLevel" => raw_issue["originalLevel"] || raw_issue["level"]
        )
        issue.remove_instance_variable(:@severity) if issue.instance_variable_defined?(:@severity)
      end

      private

      def message_id_matches?(issue_message_id)
        (@message_id || issue_message_id) == issue_message_id
      end

      def fetch_required(key)
        @config[key] || raise_invalid("Missing '#{key}'")
      end

      def severity(value, key)
        normalized = value.to_s.downcase
        raise_invalid("Invalid '#{key}'") unless SEVERITIES.include?(normalized)
        normalized
      end

      def raise_invalid(problem)
        raise ArgumentError, "#{problem} in validation_message_overrides rule: #{@config}"
      end
    end

    def self.normalize_rules(rules)
      rules.map { |rule| Rule.new(rule).config }
    end

    def message_overrides(rules = nil)
      @message_overrides = rules.map { |rule| Rule.new(rule) } if rules
      @message_overrides || []
    end

    def mark_issues_for_filtering(issues)
      apply_message_overrides(issues)
      super
    end

    private

    def apply_message_overrides(issues)
      issues.each do |issue|
        matching_override(issue)&.apply(issue)
        apply_message_overrides(issue.slice_info)
      end
    end

    def matching_override(issue)
      message_overrides.find { |rule| rule.matches?(issue) }
    end
  end
end
