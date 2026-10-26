# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "inferno_suite_generator"
require "inferno_suite_generator/plugins/testing"

module InfernoSuitePlugins
  module ProfileRead
    # Runs the plugin the way the host does and checks the plugins.yml data, the test file and the runtime files
    # it writes, and the test it adds to each group.
    class PluginTest < Minitest::Test
      include InfernoSuiteGenerator::Plugins::Testing

      PLUGIN_ROOT = File.expand_path("..", __dir__)
      PLUGIN_ID = "profile_read"
      PROFILE_URL = "http://example.org/StructureDefinition/example-patient"
      TEST_ID = "example_v100_patient_profile_read_test"
      SHALL_READ = [{ code: "read", expectation: "SHALL" }].freeze

      def setup
        @dir = Dir.mktmpdir
      end

      def teardown
        FileUtils.remove_entry(@dir)
      end

      def test_a_group_gets_its_read_data_in_plugins_yml
        run_read(build_group_metadata(interactions: SHALL_READ))

        assert_equal({ "resource_type" => "Patient", "profile_url" => PROFILE_URL, "profile_version" => "1.0.0",
                       "expectation" => "SHALL", "example_ids" => %w[pat-1 pat-2], "validate" => true,
                       "tests" => [{ "id" => TEST_ID, "file_name" => "patient_profile_read_test.rb" }] },
                     group_data)
      end

      def test_only_examples_that_claim_the_profile_are_default_ids
        run_read(build_group_metadata(interactions: SHALL_READ))

        assert_equal %w[pat-1 pat-2], group_data["example_ids"]
      end

      def test_the_test_is_added_at_the_end_of_the_group
        group = build_group_metadata(interactions: SHALL_READ, tests: [{ id: "built_in", file_name: "built_in.rb" }])

        run_read(group)

        assert_equal(%w[built_in] + [TEST_ID], group.tests.map { |test| test[:id] })
      end

      def test_the_generated_test_is_valid_ruby_with_its_inputs
        run_read(build_group_metadata(interactions: SHALL_READ))
        source = File.read(test_path)

        assert RubyVM::InstructionSequence.compile_file(test_path)
        assert_includes source, "class PatientProfileReadTest < Inferno::Test"
        assert_includes source, "id :#{TEST_ID}\n"
        assert_includes source, "input :patient_profile_read_ids,"
        assert_includes source, 'default: "pat-1, pat-2"'
        assert_includes source, "require_relative '../plugins/profile_read/profile_read_test'"
      end

      def test_a_shall_read_test_is_required
        run_read(build_group_metadata(interactions: SHALL_READ))

        refute_match(/^\s*optional$/, File.read(test_path))
      end

      def test_a_should_or_undeclared_read_test_is_optional
        [[{ code: "read", expectation: "SHOULD" }], []].each do |interactions|
          run_read(build_group_metadata(interactions:))

          assert_match(/^\s*optional$/, File.read(test_path))
        end
      end

      def test_declared_only_leaves_out_groups_without_read
        run_read(build_group_metadata(interactions: [{ code: "search-type", expectation: "SHALL" }]),
                 options: { "declared_only" => true })

        refute_path_exists test_path
        refute_path_exists File.join(@dir, "patient", "plugins.yml")
      end

      def test_validate_false_is_recorded_and_left_out_of_the_description
        run_read(build_group_metadata(interactions: SHALL_READ), options: { "validate" => false })

        refute group_data["validate"]
        refute_includes File.read(test_path), "validated against"
      end

      def test_the_runtime_module_is_installed_in_the_suite
        run_read(build_group_metadata(interactions: SHALL_READ))

        assert_path_exists File.join(@dir, "plugins", PLUGIN_ID, "profile_read_test.rb")
      end

      def test_the_generated_group_requires_and_runs_the_test
        group = build_group_metadata(interactions: SHALL_READ)
        descriptions = run_read(group)
        with_config_keeper do
          InfernoSuiteGenerator::Generator::GroupGenerator.generate(build_ig_metadata(groups: [group]), @dir,
                                                                    descriptions)
        end
        source = File.read(File.join(@dir, "patient_group.rb"))

        assert_includes source, "require_relative 'patient/patient_profile_read_test'"
        assert_includes source, "test from: :#{TEST_ID}"
      end

      private

      def run_read(group, options: {})
        run_plugin(PLUGIN_ROOT, options:, ig_metadata: build_ig_metadata(groups: [group]),
                                ig_resources: example_resources, base_output_dir: @dir)
      end

      def example_resources
        InfernoSuiteGenerator::Generator::IGResources.new.tap do |ig_resources|
          ig_resources.add(patient("pat-1", PROFILE_URL))
          ig_resources.add(patient("pat-2", "#{PROFILE_URL}|1.0.0"))
          ig_resources.add(patient("other", "http://example.org/StructureDefinition/other-patient"))
          ig_resources.add(patient("bare"))
        end
      end

      def patient(id, *profiles)
        FHIR::Patient.new(id:, meta: { profile: profiles })
      end

      def group_data
        plugin_metadata(File.join(@dir, "patient"), PLUGIN_ID)
      end

      def test_path
        File.join(@dir, "patient", "patient_profile_read_test.rb")
      end
    end
  end
end
