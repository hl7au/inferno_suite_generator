# frozen_string_literal: true

require_relative "test_helper"
require_relative "generator_fixtures"
require "minitest/mock"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  # A kit opts in to questionnaire usage tracing through configs.generic.questionnaire_usage_tracing.
  class GeneratorQuestionnaireUsageTest < Minitest::Test
    include GeneratorFixtures

    def test_off_by_default
      assert_empty run_with(configs: {})
    end

    def test_runs_over_included_groups_when_the_kit_opts_in
      kept = build_group_metadata(name: "kept", profile_url: "http://example.org/kept")
      skipped = build_group_metadata(name: "skipped", profile_url: "http://example.org/skipped")
      configs = { "generic" => { "questionnaire_usage_tracing" => true },
                  "profiles" => { "http://example.org/skipped" => { "skip_generation" => true } } }

      calls = run_with(configs:, groups: [kept, skipped])

      assert_equal 1, calls.length
      assert_equal [kept], calls.first[:groups]
    end

    private

    def run_with(configs:, groups: [])
      calls = []
      generator = Generator.new(nil)
      generator.ig_metadata = build_ig_metadata(groups:)
      with_config_keeper({ "configs" => configs }) do
        QuestionnaireUsage.stub(:generate, ->(**args) { calls << args }) { generator.generate_questionnaire_usage }
      end
      calls
    end
  end
end
