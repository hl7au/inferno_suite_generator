# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "inferno_suite_generator"
require "inferno_suite_generator/plugins/testing"

module InfernoSuiteGenerator
  # Built-in generators record each test's kind and details on the group, so Plugins::TestIndex finds them.
  class GeneratorTestKindsTest < Minitest::Test
    include Plugins::Testing

    def setup
      @dir = Dir.mktmpdir
      @search = { names: %w[name birthdate], expectation: "SHALL" }
      @group = build_group_metadata(
        searches: [@search],
        search_definitions: { name: { path: "Patient.name" }, birthdate: { path: "Patient.birthDate" } }
      )
      @ig_metadata = build_ig_metadata(groups: [@group])
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def test_search_test_records_its_kind_and_parameter_names
      with_config_keeper do
        generator = Generator::SearchTestGenerator.new(@group, @search, @dir, @ig_metadata)
        generator.define_singleton_method(:output) { "" }
        generator.generate

        assert_equal({ kind: "search", search_names: %w[name birthdate] }, @group.test_kind(generator.test_id))
        assert_equal generator.test_id, Plugins::TestIndex.new(@group).find("search", search_names: %w[birthdate name])
      end
    end

    def test_include_test_adds_its_targets
      generator = Generator::IncludeSearchTestGenerator.new(@group, @search, @dir, {}, @ig_metadata)
      generator.define_singleton_method(:includes) { [{ "target_resource" => "Practitioner" }] }

      assert_equal({ search_names: %w[name birthdate], include_targets: ["Practitioner"] }, generator.test_details)
    end
  end
end
