# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "inferno_suite_generator"
require "inferno_suite_generator/plugins/scaffold"
require "inferno_suite_generator/plugins/testing"

module InfernoSuiteGenerator
  module Plugins
    class ScaffoldTest < Minitest::Test
      include Testing

      def setup
        @dir = Dir.mktmpdir
        @destination = File.join(@dir, "my_sample")
      end

      def teardown
        FileUtils.remove_entry(@dir)
      end

      def test_creates_plugin_files
        written = Scaffold.new(id: "my_sample", destination: @destination).create

        assert_equal(
          %w[AGENTS.md README.md lib/my_sample.rb lib/my_sample/extractor.rb lib/my_sample/plugin.rb plugin.yml
             test/my_sample_test.rb],
          written.map { |path| path.delete_prefix("#{@destination}/") }.sort
        )
        assert_equal "InfernoSuitePlugins::MySample::Plugin", Manifest.load(@destination).class_name
      end

      def test_scaffolded_plugin_loads_and_writes_group_metadata
        Scaffold.new(id: "my_sample", destination: @destination).create
        base_output_dir = File.join(@dir, "out")

        run_plugin(@destination, ig_metadata: build_ig_metadata(groups: [build_group_metadata]), base_output_dir:)

        assert_equal "Patient", plugin_metadata(File.join(base_output_dir, "patient"), "my_sample")["resource"]
      end

      def test_refuses_existing_destination_and_invalid_id
        FileUtils.mkdir_p(@destination)

        assert_raises(Error) { Scaffold.new(id: "my_sample", destination: @destination).create }
        assert_raises(Error) { Scaffold.new(id: "MySample", destination: @destination) }
      end
    end
  end
end
