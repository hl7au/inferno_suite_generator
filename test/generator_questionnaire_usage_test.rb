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

    def test_runs_over_the_groups_in_the_order_the_group_files_are_written
      first = build_group_metadata(name: "first", profile_url: "http://example.org/first")
      second = build_group_metadata(name: "second", profile_url: "http://example.org/second")
      generator = Generator.new(nil)
      generator.ig_metadata = build_ig_metadata(groups: [second, first])
      generator.ig_metadata.stub(:ordered_groups, [first, nil, second]) do
        calls = traced(generator, { "generic" => { "questionnaire_usage_tracing" => true } })

        assert_equal [first, second], calls.first[:groups]
      end
    end

    private

    def run_with(configs:, groups: [])
      generator = Generator.new(nil)
      generator.ig_metadata = build_ig_metadata(groups:)
      traced(generator, configs)
    end

    def traced(generator, configs)
      calls = []
      with_config_keeper({ "configs" => configs }) do
        QuestionnaireUsage.stub(:descriptions, ->(**args) { calls << args }) { generator.generate_questionnaire_usage }
      end
      calls
    end
  end
end
