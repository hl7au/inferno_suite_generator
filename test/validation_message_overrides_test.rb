# frozen_string_literal: true

require_relative "test_helper"
require "inferno/dsl/fhir_resource_validation"
require "inferno/entities/attributes"
require "inferno/entities/entity"
require "inferno/entities/message"
require "inferno_suite_generator/utils/validation_message_overrides"

module InfernoSuiteGenerator
  class ValidationMessageOverridesTest < Minitest::Test
    Validator = Inferno::DSL::FHIRResourceValidation::Validator
    ValidatorResponse = Struct.new(:status, :body)

    MIME_TYPE_MESSAGE = "The value provided ('xml') was not found in the value set 'MimeType'"

    class RunnableDouble
      attr_reader :messages

      def initialize
        @messages = []
      end

      def add_message(type, message)
        @messages << { type:, message: }
      end
    end

    def setup
      @runnable = RunnableDouble.new
      @target = { "resourceType" => "Patient" }
    end

    def test_matching_rule_downgrades_error_to_warning_and_passes
      validator = build_validator([{ "pattern" => "not found in the value set 'MimeType'", "to" => "warning" }])

      assert validator.conformant?(@target, "http://example.org/profile", @runnable)
      assert_equal [{ type: "warning", message: "Patient.content: #{MIME_TYPE_MESSAGE}" }], @runnable.messages
    end

    def test_matching_rule_upgrades_warning_to_error_and_fails
      validator = build_validator([{ "pattern" => "MimeType", "to" => "error" }], level: "WARNING")

      refute validator.conformant?(@target, "http://example.org/profile", @runnable)
      assert_equal ["error"], message_types
    end

    def test_rule_with_non_matching_from_leaves_issue_unchanged
      validator = build_validator([{ "pattern" => "MimeType", "from" => ["warning"], "to" => "info" }])

      refute validator.conformant?(@target, "http://example.org/profile", @runnable)
      assert_equal ["error"], message_types
    end

    def test_rule_with_non_matching_location_leaves_issue_unchanged
      validator = build_validator([{ "pattern" => "MimeType", "location" => "^Bundle\\.entry", "to" => "info" }])

      refute validator.conformant?(@target, "http://example.org/profile", @runnable)
    end

    def test_rule_matches_on_message_id
      validator = build_validator([{ "pattern" => ".*", "message_id" => "Terminology_TX_NotValid", "to" => "info" }])

      assert validator.conformant?(@target, "http://example.org/profile", @runnable)
      assert_equal ["info"], message_types
    end

    def test_first_matching_rule_wins
      validator = build_validator([
                                    { "pattern" => "MimeType", "to" => "info" },
                                    { "pattern" => "MimeType", "to" => "warning" }
                                  ])

      validator.conformant?(@target, "http://example.org/profile", @runnable)
      assert_equal ["info"], message_types
    end

    def test_rules_apply_to_slice_info
      slice_issue = raw_issue(level: "ERROR", message: "Slice 'a' is not handled")
      validator = build_validator([{ "pattern" => "Slice '.*' is not handled", "to" => "info" }],
                                  slice_info: [slice_issue])
      details = []

      validator.conformant?(@target, "http://example.org/profile", @runnable, validator_response_details: details)

      slice = details.first.slice_info.first
      assert_equal "info", slice.severity
      assert_equal "ERROR", slice.raw_issue["originalLevel"]
      assert_equal "error", details.first.severity
    end

    def test_overridden_severity_is_visible_to_exclude_message
      seen_types = []
      validator = build_validator([{ "pattern" => "MimeType", "to" => "warning" }]) do
        exclude_message do |message|
          seen_types << message.type
          false
        end
      end

      validator.conformant?(@target, "http://example.org/profile", @runnable)
      assert_equal ["warning"], seen_types
    end

    def test_without_rules_behaviour_is_unchanged
      validator = build_validator([])

      refute validator.conformant?(@target, "http://example.org/profile", @runnable)
      assert_equal ["error"], message_types
    end

    private

    def message_types
      @runnable.messages.map { |message| message[:type] }
    end

    def build_validator(rules, level: "ERROR", slice_info: nil, &extra)
      response = validator_response(level:, slice_info:)
      validator = Validator.new(:default, "test_suite") do
        extend InfernoSuiteGenerator::ValidationMessageOverrides

        message_overrides rules
        instance_eval(&extra) if extra
      end
      validator.define_singleton_method(:call_validator) { |_target, _profile_url| response }
      validator
    end

    def validator_response(level:, slice_info:)
      issue = raw_issue(level:, message: MIME_TYPE_MESSAGE)
      issue["sliceInfo"] = slice_info if slice_info
      ValidatorResponse.new(200, { "outcomes" => [{ "issues" => [issue] }] }.to_json)
    end

    def raw_issue(level:, message:)
      {
        "level" => level,
        "location" => "Patient.content",
        "message" => message,
        "messageId" => "Terminology_TX_NotValid"
      }
    end
  end
end
