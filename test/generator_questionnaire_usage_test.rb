# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"
require "tmpdir"

module InfernoSuiteGenerator
  class GeneratorQuestionnaireUsageTest < Minitest::Test
    GeneratorConfigKeeper = InfernoSuiteGenerator::Generator::GeneratorConfigKeeper
    GroupGenerator = InfernoSuiteGenerator::Generator::GroupGenerator

    SKIPPED_PROFILE = "http://example.org/StructureDefinition/skipped-patient"

    Group = Struct.new(:profile_url, :resource)
    FakeIGMetadata = Struct.new(:ordered_groups, :ig_version)

    STEPS_BEFORE = %i[load_ig_package extract_metadata extract_demodata generate_search_tests generate_read_tests
                      generate_provenance_revinclude_search_tests generate_include_search_tests
                      generate_validation_tests generate_must_support_tests generate_reference_resolution_tests
                      generate_create_tests generate_update_tests generate_patch_tests].freeze
    STEPS_AFTER = %i[generate_suites use_tests].freeze

    def setup
      @dir = Dir.mktmpdir
      @previous_config_keeper = Registry.get(:config_keeper)
      @kept = Group.new("http://example.org/StructureDefinition/patient", "Patient")
      @skipped = Group.new(SKIPPED_PROFILE, "Patient")
      @calls = []
    end

    def teardown
      Registry.register(:config_keeper, @previous_config_keeper)
      FileUtils.remove_entry(@dir)
    end

    def test_flag_on_traces_only_non_excluded_groups_once
      generator = generator_with(tracing: true)

      result = record_descriptions { generator.generate_questionnaire_usage }

      assert_equal [{ ig_resources: :resources, groups: [@kept] }], @calls
      assert_equal({ @kept => { group: "text" } }, result)
    end

    def test_flag_off_does_not_trace
      generator = generator_with(tracing: false)

      record_descriptions { generator.generate_questionnaire_usage }

      assert_empty @calls
    end

    def test_generate_traces_after_patch_tests_and_passes_result_to_groups
      generator = generator_with(tracing: true)
      steps = record_steps(generator)
      group_args = nil

      stub = lambda do |*args|
        group_args = args
        steps << :generate_groups
      end
      GroupGenerator.stub(:generate, stub) { record_descriptions { generator.generate } }

      assert_equal STEPS_BEFORE + %i[generate_groups] + STEPS_AFTER, steps
      assert_equal [{ @kept => { group: "text" } }], group_args.drop(2)
    end

    def test_groups_get_empty_descriptions_when_flag_is_off
      generator = generator_with(tracing: false)
      group_args = nil

      GroupGenerator.stub(:generate, ->(*args) { group_args = args }) { generator.generate_groups }

      assert_equal({}, group_args.last)
    end

    private

    def generator_with(tracing:)
      configs = { "generic" => { "questionnaire_usage_tracing" => tracing },
                  "profiles" => { SKIPPED_PROFILE => { "skip_generation" => true } } }
      path = File.join(@dir, "config.json")
      File.write(path, JSON.generate({ "ig" => {}, "suite" => { "title" => "Example" }, "configs" => configs }))
      Registry.register(:config_keeper, GeneratorConfigKeeper.new([path]))

      Generator.new(@dir).tap do |generator|
        generator.ig_resources = :resources
        generator.ig_metadata = FakeIGMetadata.new([@skipped, nil, @kept], "v1")
      end
    end

    def record_steps(generator)
      [].tap do |steps|
        (STEPS_BEFORE + STEPS_AFTER).each { |step| generator.define_singleton_method(step) { steps << step } }
      end
    end

    def record_descriptions(&)
      recorder = lambda do |**kwargs|
        @calls << kwargs
        kwargs[:groups].to_h { |group| [group, { group: "text" }] }
      end
      QuestionnaireUsage.stub(:descriptions, recorder, &)
    end
  end
end
