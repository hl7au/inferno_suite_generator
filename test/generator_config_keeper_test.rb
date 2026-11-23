# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"
require "tmpdir"

module InfernoSuiteGenerator
  class GeneratorConfigKeeperTest < Minitest::Test
    GeneratorConfigKeeper = InfernoSuiteGenerator::Generator::GeneratorConfigKeeper
    Constants = GeneratorConfigKeeper::Constants

    def setup
      @dir = Dir.mktmpdir
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def write_config(name, extra = {})
      path = File.join(@dir, "#{name}.json")
      File.write(path, JSON.generate({ "ig" => {}, "suite" => {}, "configs" => {} }.merge(extra)))
      path
    end

    def keeper_with(extra)
      GeneratorConfigKeeper.new([write_config("config", extra)])
    end

    def test_second_keeper_does_not_see_first_keepers_config
      tracing_on = { "generic" => { "questionnaire_usage_tracing" => true } }
      first = GeneratorConfigKeeper.new([write_config("a", "only_in_a" => 1, "configs" => tracing_on)])
      second = GeneratorConfigKeeper.new([write_config("b")])

      assert first.questionnaire_usage_tracing?
      refute second.config.key?("only_in_a")
      refute second.questionnaire_usage_tracing?
      assert_empty Constants::EMPTY_MUTABLE_HASH
    end

    def test_reload_rebuilds_from_own_files_only
      GeneratorConfigKeeper.new([write_config("a", "only_in_a" => 1)])
      path = write_config("b")
      keeper = GeneratorConfigKeeper.new([path])
      File.write(path, JSON.generate({ "ig" => {}, "suite" => {}, "configs" => {}, "only_in_b" => 1 }))

      config = keeper.reload

      assert_equal %w[configs ig only_in_b suite], config.keys.sort
      assert_empty Constants::EMPTY_MUTABLE_HASH
    end

    def test_questionnaire_usage_tracing_only_for_json_true
      assert keeper_with("configs" => { "generic" => { "questionnaire_usage_tracing" => true } })
        .questionnaire_usage_tracing?
      refute keeper_with({}).questionnaire_usage_tracing?
      refute keeper_with("configs" => { "generic" => {} }).questionnaire_usage_tracing?
      [false, "true", 1, nil].each do |value|
        refute keeper_with("configs" => { "generic" => { "questionnaire_usage_tracing" => value } })
          .questionnaire_usage_tracing?, "expected false for #{value.inspect}"
      end
    end

    def test_empty_mutable_hash_is_still_defined
      assert_equal({}, Constants::EMPTY_MUTABLE_HASH)
    end

    def test_signatures_declare_flag_and_keep_empty_mutable_hash
      sig = File.read(File.expand_path("../sig/inferno_suite_generator.rbs", __dir__))
      getters = sig[/module Getters\b.*?\n\s*end\n/m]

      assert_includes getters, "def questionnaire_usage_tracing?: () -> bool"
      assert_includes sig, "EMPTY_MUTABLE_HASH: Hash[untyped, untyped]"
    end
  end
end
