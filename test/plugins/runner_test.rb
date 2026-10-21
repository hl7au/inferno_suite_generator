# frozen_string_literal: true

require_relative "../test_helper"
require_relative "plugin_fixtures"
require "tmpdir"
require "inferno_suite_generator"
require "inferno_suite_generator/plugins/testing"

module InfernoSuiteGenerator
  module Plugins
    class RunnerTest < Minitest::Test
      include PluginFixtures
      include Testing

      def setup
        @dir = Dir.mktmpdir
      end

      def teardown
        FileUtils.remove_entry(@dir)
      end

      PROBE = <<~RUBY
        def generate(context)
          context.metadata.suite(
            "plugin_id" => context.plugin_id, "options" => context.options,
            "groups" => context.groups.map(&:resource), "ig_version" => context.ig_metadata.ig_version
          )
        end
      RUBY

      def test_passes_host_inputs_options_and_metadata_writer_to_generate
        root = File.join(@dir, "plugin")
        write_plugin(root, id: "probe", body: PROBE)
        base_output_dir = File.join(@dir, "out")

        run_plugin(root, ig_metadata: build_ig_metadata(groups: [build_group_metadata]), base_output_dir:,
                         options: { "flag" => true })

        assert_equal(
          { "plugin_id" => "probe", "options" => { "flag" => true }, "groups" => ["Patient"], "ig_version" => "1.0.0" },
          plugin_metadata(base_output_dir, "probe")
        )
      end

      def test_context_groups_leave_out_skipped_resources
        root = File.join(@dir, "plugin")
        write_plugin(root, id: "skips", body: <<~RUBY)
          def generate(context)
            context.metadata.suite("groups" => context.groups.map(&:resource))
          end
        RUBY
        groups = [build_group_metadata, build_group_metadata(name: "example_location", resource: "Location")]
        config = { "configs" => { "resources" => { "Location" => { "skip_generation" => true } } } }

        run_plugin(root, ig_metadata: build_ig_metadata(groups:), base_output_dir: @dir, config:)

        assert_equal ["Patient"], plugin_metadata(@dir, "skips")["groups"]
      end

      def test_install_runtime_copies_runtime_directory_into_suite
        root = File.join(@dir, "plugin")
        write_plugin(root, id: "with_runtime", body: "def generate(context) = context.install_runtime")
        FileUtils.mkdir_p(File.join(root, "runtime"))
        File.write(File.join(root, "runtime", "helper.rb"), "# helper\n")
        base_output_dir = File.join(@dir, "out")

        run_plugin(root, ig_metadata: build_ig_metadata(groups: []), base_output_dir:)

        assert_equal "# helper\n", File.read(File.join(base_output_dir, "plugins", "with_runtime", "helper.rb"))
      end

      RUNS = [] # rubocop:disable Style/MutableConstant
      RECORD_RUN = "def generate(context) = InfernoSuiteGenerator::Plugins::RunnerTest::RUNS << context.plugin_id"

      def test_runs_plugins_in_config_order
        RUNS.clear
        %w[second first].each { |id| write_plugin(File.join(@dir, id), id:, body: RECORD_RUN) }
        plugins = Loader.new({ "second" => { "path" => "second" }, "first" => { "path" => "first" } },
                             base_dir: @dir).load

        capture_io { Runner.new(plugins).run(**host) }

        assert_equal %w[second first], RUNS
      end

      def test_runs_nothing_and_writes_nothing_without_plugins
        Runner.new.run(base_output_dir: @dir)

        assert_empty Dir.children(@dir)
      end

      private

      def host
        { ig_resources: nil, ig_metadata: nil, ig_demodata: nil, base_output_dir: @dir, config: nil }
      end
    end
  end
end
