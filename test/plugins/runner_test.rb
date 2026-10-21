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

      def test_plugin_tells_whether_a_plugin_id_is_enabled
        write_plugin(File.join(@dir, "read"), id: "read", body: RECORD_RUN)
        runner = Runner.new(Loader.new({ "read" => { "path" => "read" } }, base_dir: @dir).load)

        assert runner.plugin?("read")
        refute runner.plugin?("other")
        refute Runner.new.plugin?("read")
      end

      def test_runs_nothing_and_writes_nothing_without_plugins
        Runner.new.run(base_output_dir: @dir)

        assert_empty Dir.children(@dir)
      end

      DESCRIBE = <<~'RUBY'
        def generate(context) = context.descriptions.group(context.ig_metadata.groups.first, "## #{context.plugin_id}")
      RUBY

      def test_run_plugin_returns_the_group_descriptions_the_plugin_added
        write_plugin(File.join(@dir, "extra"), id: "extra", body: DESCRIBE)
        group = build_group_metadata

        descriptions = run_plugin(File.join(@dir, "extra"), ig_metadata: build_ig_metadata(groups: [group]),
                                                            base_output_dir: @dir)

        assert_equal ["## extra"], descriptions.for(group)
      end

      def test_runner_keeps_group_descriptions_in_config_order
        group = build_group_metadata
        %w[second first].each { |id| write_plugin(File.join(@dir, id), id:, body: DESCRIBE) }
        runner = Runner.new(Loader.new({ "second" => { "path" => "second" }, "first" => { "path" => "first" } },
                                       base_dir: @dir).load)

        capture_io { runner.run(**host, ig_metadata: build_ig_metadata(groups: [group])) }

        assert_equal ["## second", "## first"], runner.group_descriptions.for(group)
      end

      def test_runner_without_plugins_has_no_group_descriptions
        assert_empty Runner.new.group_descriptions.for(build_group_metadata)
      end

      private

      def host
        { ig_resources: nil, ig_metadata: nil, ig_demodata: nil, base_output_dir: @dir, config: nil }
      end
    end
  end
end
