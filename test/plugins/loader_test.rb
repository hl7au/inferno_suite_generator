# frozen_string_literal: true

require_relative "../test_helper"
require_relative "plugin_fixtures"
require "tmpdir"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  module Plugins
    class LoaderTest < Minitest::Test
      include PluginFixtures

      def setup
        @dir = Dir.mktmpdir
      end

      def teardown
        FileUtils.remove_entry(@dir)
      end

      def test_loads_folder_plugin_relative_to_base_dir
        class_name = write_plugin(File.join(@dir, "plugins/sample"), id: "sample")

        plugins = Loader.new({ "sample" => { "path" => "plugins/sample", "options" => { "a" => 1 } } },
                             base_dir: @dir).load

        assert_equal(["sample"], plugins.map(&:id))
        assert_instance_of Object.const_get(class_name), plugins.first.instance
        assert_equal({ "a" => 1 }, plugins.first.options)
      end

      def test_keeps_config_order_and_skips_disabled_plugins
        write_plugin(File.join(@dir, "b"), id: "b_plugin")
        write_plugin(File.join(@dir, "a"), id: "a_plugin")
        write_plugin(File.join(@dir, "c"), id: "c_plugin")
        entries = {
          "b_plugin" => { "path" => "b" }, "c_plugin" => { "path" => "c", "enabled" => false },
          "a_plugin" => { "path" => "a" }
        }

        assert_equal(%w[b_plugin a_plugin], Loader.new(entries, base_dir: @dir).load.map(&:id))
      end

      def test_loads_builtin_plugin_from_gem_plugins_directory
        plugins = Loader.new({ "read" => { "builtin" => "read" } }).load

        assert_equal File.join(Loader::BUILTIN_ROOT, "read"), plugins.first.manifest.root
      end

      def test_raises_when_no_or_several_sources_given
        assert_raises(Error) { Loader.new({ "x" => {} }).load }
        error = assert_raises(Error) { Loader.new({ "x" => { "path" => "a", "gem" => "b" } }).load }

        assert_match "must set exactly one of path, gem, builtin", error.message
      end

      def test_raises_when_gem_is_not_installed
        error = assert_raises(Error) { Loader.new({ "x" => { "gem" => "no_such_plugin_gem_xyz" } }).load }

        assert_match "not installed", error.message
      end

      def test_raises_when_config_key_and_manifest_id_differ
        write_plugin(@dir, id: "actual")

        error = assert_raises(Error) { Loader.new({ "configured" => { "path" => @dir } }).load }

        assert_match 'its plugin.yml says id "actual"', error.message
      end

      def test_raises_when_class_is_not_defined
        write_plugin(@dir, id: "missing_class")
        File.write(File.join(@dir, "lib", "missing_class.rb"), "")

        error = assert_raises(Error) { Loader.new({ "missing_class" => { "path" => @dir } }).load }

        assert_match "is not defined", error.message
      end

      def test_raises_when_generate_does_not_take_context
        write_plugin(@dir, id: "no_args", body: "def generate; end")

        error = assert_raises(Error) { Loader.new({ "no_args" => { "path" => @dir } }).load }

        assert_match "must define generate(context)", error.message
      end
    end
  end
end
