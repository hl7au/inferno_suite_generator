# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "inferno_suite_generator"
require "inferno_suite_generator/plugins/testing"

module InfernoSuiteGenerator
  module Plugins
    class MetadataStoreTest < Minitest::Test
      include Testing

      def setup
        @dir = Dir.mktmpdir
        @previous_config_keeper = Registry.get(:config_keeper)
        Registry.register(:config_keeper, build_config_keeper)
        @store = MetadataStore.new(@dir)
        @group = build_group_metadata
      end

      def teardown
        Registry.register(:config_keeper, @previous_config_keeper)
        FileUtils.remove_entry(@dir)
      end

      def test_writes_group_and_suite_files_keyed_by_plugin_id
        @store.for_plugin("first").group(@group, { tests: [{ id: :x }] })
        @store.for_plugin("second").group(@group, { "flag" => true })
        @store.for_plugin("first").suite({ "version" => "1" })
        @store.flush

        assert_equal(
          { "first" => { "tests" => [{ "id" => :x }] }, "second" => { "flag" => true } },
          YAML.safe_load_file(File.join(@dir, "patient", "plugins.yml"), permitted_classes: [Symbol])
        )
        assert_equal({ "first" => { "version" => "1" } }, YAML.safe_load_file(File.join(@dir, "plugins.yml")))
      end

      def test_deep_merges_repeated_writes_and_appends_arrays
        writer = @store.for_plugin("first")
        writer.group(@group, { "a" => { "x" => 1 }, "b" => 1, "tests" => ["t1"] })
        writer.group(@group, { "a" => { "y" => 2 }, "b" => 2, "tests" => ["t2"] })
        @store.flush

        assert_equal({ "a" => { "x" => 1, "y" => 2 }, "b" => 2, "tests" => %w[t1 t2] },
                     plugin_metadata(File.join(@dir, "patient"), "first"))
      end

      def test_writes_extractor_results
        @store.for_plugin("first").groups({ @group => { "a" => 1 } })
        @store.flush

        assert_equal({ "a" => 1 }, plugin_metadata(File.join(@dir, "patient"), "first"))
      end

      def test_writes_nothing_before_flush_and_leaves_host_metadata_alone
        @store.for_plugin("first").group(@group, { "a" => 1 })

        refute_path_exists File.join(@dir, "patient")
      end

      def test_runtime_metadata_is_empty_without_file_or_plugin_section
        assert_empty RuntimeMetadata.load(@dir, "first")

        @store.for_plugin("first").suite({ "a" => 1 })
        @store.flush

        assert_empty RuntimeMetadata.load(@dir, "other")
      end
    end
  end
end
