# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "inferno_suite_generator"
require "inferno_suite_generator/plugins/testing"

module InfernoSuitePlugins
  module Read
    # Runs the read plugin end to end and checks its output against the built-in ReadTestGenerator.
    class PluginTest < Minitest::Test
      include InfernoSuiteGenerator::Plugins::Testing

      PLUGIN_ROOT = File.expand_path("..", __dir__)
      READ = { code: "read", expectation: "SHALL" }.freeze
      FIRST_CLASS_PATIENT = {
        "configs" => { "resources" => { "Patient" => { "first_class_profile" => "read" } } },
        "constants" => { "read_ids.patient" => "pat-1, pat-2" }
      }.freeze

      # What the plugin's read test has instead of the built-in one, as [built-in text, plugin text].
      PLUGIN_ONLY_DIFFERENCES = [
        ["require 'inferno_suite_generator/test_modules/read_test'\n",
         "require_relative '../plugins/read/read_test'\nrequire 'inferno_suite_generator/plugins/runtime_metadata'\n"],
        ["include InfernoSuiteGenerator::ReadTest", "include InfernoSuitePlugins::Read::ReadTest"]
      ].freeze
      PLUGIN_ONLY_ACCESSOR = /^ *def self\.plugin_metadata\n.*?\n *end\n\n/m

      def setup
        @dir = Dir.mktmpdir
      end

      def teardown
        FileUtils.remove_entry(@dir)
      end

      def test_generates_read_test_only_for_groups_with_read_interaction
        patient = build_group_metadata(resource: "Patient", interactions: [READ])
        location = build_group_metadata(name: "example_location", resource: "Location", interactions: [])

        run_read_plugin([patient, location])

        assert_path_exists File.join(@dir, "patient", "patient_read_test.rb")
        refute_path_exists File.join(@dir, "location")
        assert_equal [{ id: "example_v100_patient_read_test", file_name: "patient_read_test.rb" }], patient.tests
      end

      def test_writes_group_plugin_metadata
        run_read_plugin([build_group_metadata(interactions: [READ])])

        assert_equal(
          {
            "interaction" => { "code" => "read", "expectation" => "SHALL" },
            "tests" => [{ "id" => "example_v100_patient_read_test", "file_name" => "patient_read_test.rb" }]
          },
          plugin_metadata(File.join(@dir, "patient"), "read")
        )
      end

      def test_adds_ids_input_for_first_class_read_profiles
        run_read_plugin([build_group_metadata(interactions: [READ])], config: FIRST_CLASS_PATIENT)

        assert_equal(
          { "input_id" => "patient_ids", "title" => "Patient IDs", "default" => "pat-1, pat-2",
            "description" => "Comma separated list of patient IDs that in sum contain all MUST SUPPORT elements" },
          plugin_metadata(File.join(@dir, "patient"), "read")["ids_input"]
        )
        assert_includes File.read(File.join(@dir, "patient", "patient_read_test.rb")), "input :patient_ids"
      end

      def test_places_read_test_after_plain_searches_and_before_include_and_validation_tests
        ids = %w[x_patient_name_search_test x_patient_name_gender_multiple_and_search_test
                 x_patient_organization_name_chain_search_test x_patient_name_include_name_search_test
                 x_patient_validation_test]
        group = build_group_metadata(interactions: [READ], searches: [{ names: ["patient"] }],
                                     tests: ids.map { |id| { id:, file_name: "#{id}.rb" } })

        run_read_plugin([group])

        assert_equal(ids.insert(3, "example_v100_patient_read_test"), group.tests.map { |test| test[:id] })
      end

      def test_places_read_test_first_in_delayed_groups
        group = build_group_metadata(name: "example_location", resource: "Location", interactions: [READ],
                                     tests: [{ id: "x_location_address_search_test", file_name: "x.rb" }])

        run_read_plugin([group])

        assert_equal "example_v100_location_read_test", group.tests.first[:id]
      end

      def test_installs_runtime_module_where_the_generated_test_requires_it
        run_read_plugin([build_group_metadata(interactions: [READ])])

        assert_equal File.read(File.join(PLUGIN_ROOT, "runtime", "read_test.rb")),
                     File.read(File.join(@dir, "plugins", "read", "read_test.rb"))
      end

      def test_refuses_to_generate_a_test_the_group_already_has
        group = build_group_metadata(interactions: [READ])
        group.add_test(id: "example_v100_patient_read_test", file_name: "patient_read_test.rb")

        error = assert_raises(InfernoSuiteGenerator::Plugins::Error) { run_read_plugin([group]) }

        assert_match "generates test example_v100_patient_read_test, which group example_patient already has",
                     error.message
      end

      def test_output_matches_builtin_read_test_apart_from_runtime_module_and_metadata_accessor
        run_read_plugin([build_group_metadata(interactions: [READ])], config: FIRST_CLASS_PATIENT)
        builtin = run_builtin_read_generator([build_group_metadata(interactions: [READ])], FIRST_CLASS_PATIENT)

        plugin = File.read(File.join(@dir, "patient", "patient_read_test.rb")).sub(PLUGIN_ONLY_ACCESSOR, "")
        PLUGIN_ONLY_DIFFERENCES.each { |builtin_text, plugin_text| plugin = plugin.sub(plugin_text, builtin_text) }

        assert_equal builtin, plugin
      end

      private

      def run_read_plugin(groups, config: {})
        run_plugin(PLUGIN_ROOT, ig_metadata: build_ig_metadata(groups:), base_output_dir: @dir, config:)
      end

      # Returns the built-in generator's patient read test.
      def run_builtin_read_generator(groups, config)
        output_dir = File.join(@dir, "builtin")
        with_config_keeper(config) do
          InfernoSuiteGenerator::Generator::ReadTestGenerator.generate(build_ig_metadata(groups:), output_dir)
        end
        File.read(File.join(output_dir, "patient", "patient_read_test.rb"))
      end
    end
  end
end
