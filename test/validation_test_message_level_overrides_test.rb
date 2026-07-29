# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"
require "inferno_suite_generator/test_modules/validation_test"

module InfernoSuiteGenerator
  # Test double that includes ValidationTest and stubs out the Inferno runtime dependencies
  # (`resource_is_valid?`, `check_for_dar`) that `validate_and_check_dar` relies on, so the
  # message level override behavior can be exercised without a real validator or Inferno::Test.
  class TestableValidationTest
    include ValidationTest

    attr_reader :messages

    def initialize(fake_messages_by_resource:, level_overrides: [])
      @messages = []
      @fake_messages_by_resource = fake_messages_by_resource
      @level_overrides = level_overrides
    end

    def validation_message_level_overrides
      @level_overrides
    end

    # rubocop:disable Lint/UnusedMethodArgument -- profile_url kept to match the real resource_is_valid? signature
    def resource_is_valid?(resource:, profile_url: nil)
      @fake_messages_by_resource[resource].each { |message| @messages << message.dup }
    end
    # rubocop:enable Lint/UnusedMethodArgument

    def check_for_dar(_resource); end
  end

  class ValidationTestMessageLevelOverridesTest < Minitest::Test
    def test_matching_message_has_level_overridden
      subject = build_subject(
        messages_by_resource: { "res1" => [{ type: "error", message: "The value provided ('xml') is bad" }] },
        level_overrides: [{ "regex" => "The value provided", "level" => "warning" }]
      )

      subject.send(:validate_and_check_dar, ["res1"], "http://example.com/profile")

      assert_equal "warning", subject.messages.first[:type]
    end

    def test_non_matching_message_is_left_unchanged
      subject = build_subject(
        messages_by_resource: { "res1" => [{ type: "error", message: "Completely unrelated issue" }] },
        level_overrides: [{ "regex" => "The value provided", "level" => "warning" }]
      )

      subject.send(:validate_and_check_dar, ["res1"], "http://example.com/profile")

      assert_equal "error", subject.messages.first[:type]
    end

    def test_no_overrides_configured_leaves_messages_untouched
      subject = build_subject(
        messages_by_resource: { "res1" => [{ type: "error", message: "The value provided ('xml') is bad" }] },
        level_overrides: []
      )

      subject.send(:validate_and_check_dar, ["res1"], "http://example.com/profile")

      assert_equal "error", subject.messages.first[:type]
    end

    def test_only_messages_from_current_resource_are_considered
      subject = build_subject(
        messages_by_resource: {
          "res1" => [{ type: "error", message: "The value provided ('xml') is bad" }],
          "res2" => [{ type: "error", message: "A different unrelated message" }]
        },
        level_overrides: [{ "regex" => "The value provided", "level" => "warning" }]
      )

      subject.send(:validate_and_check_dar, %w[res1 res2], "http://example.com/profile")

      assert_equal "warning", subject.messages[0][:type]
      assert_equal "error", subject.messages[1][:type]
    end

    def test_first_matching_override_wins
      subject = build_subject(
        messages_by_resource: { "res1" => [{ type: "error", message: "The value provided ('xml') is bad" }] },
        level_overrides: [
          { "regex" => "The value provided", "level" => "warning" },
          { "regex" => "is bad", "level" => "info" }
        ]
      )

      subject.send(:validate_and_check_dar, ["res1"], "http://example.com/profile")

      assert_equal "warning", subject.messages.first[:type]
    end

    private

    def build_subject(messages_by_resource:, level_overrides:)
      TestableValidationTest.new(fake_messages_by_resource: messages_by_resource, level_overrides:)
    end
  end

  class HelpersMessageMatchingTest < Minitest::Test
    def test_message_matches_any_pattern_returns_true_on_match
      message = "The value provided ('xml') was not found in the value set 'MimeType'"

      assert Helpers.message_matches_any_pattern?(["not found in the value set"], message)
    end

    def test_message_matches_any_pattern_returns_false_when_no_pattern_matches
      refute Helpers.message_matches_any_pattern?(["unrelated pattern"], "The value provided is bad")
    end

    def test_message_level_override_returns_matching_level
      overrides = [{ "regex" => "not found in the value set", "level" => "warning" }]
      message = "The value provided ('xml') was not found in the value set 'MimeType'"

      assert_equal "warning", Helpers.message_level_override(overrides, message)
    end

    def test_message_level_override_returns_nil_when_no_match
      overrides = [{ "regex" => "unrelated", "level" => "warning" }]

      assert_nil Helpers.message_level_override(overrides, "The value provided is bad")
    end
  end
end
