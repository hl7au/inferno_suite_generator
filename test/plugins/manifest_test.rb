# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "inferno_suite_generator/plugins/manifest"

module InfernoSuiteGenerator
  module Plugins
    class ManifestTest < Minitest::Test
      VALID = {
        "id" => "read", "name" => "Read", "version" => "1.0.0", "entrypoint" => "lib/read.rb",
        "class" => "InfernoSuitePlugins::Read::Plugin"
      }.freeze

      def test_resolves_paths_against_the_plugin_root
        manifest = Manifest.new("/plugins/read", VALID)

        assert_equal "/plugins/read/lib/read.rb", manifest.entrypoint_path
        assert_equal "/plugins/read/templates", manifest.templates_dir
        assert_equal "/plugins/read/runtime", manifest.runtime_dir
      end

      def test_loads_plugin_yml_from_root
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, "plugin.yml"), YAML.dump(VALID))

          assert_equal "read", Manifest.load(dir).id
        end
      end

      def test_raises_when_plugin_yml_is_missing
        Dir.mktmpdir do |dir|
          error = assert_raises(Error) { Manifest.load(dir) }

          assert_match "Plugin manifest not found", error.message
        end
      end

      def test_raises_on_missing_required_keys
        error = assert_raises(Error) { Manifest.new("/p", VALID.except("class", "entrypoint")) }

        assert_match "is missing entrypoint, class", error.message
      end

      def test_raises_on_non_snake_case_id
        error = assert_raises(Error) { Manifest.new("/p", VALID.merge("id" => "My-Plugin")) }

        assert_match "invalid id", error.message
      end

      def test_accepts_satisfied_host_version
        assert Manifest.new("/p", VALID.merge("host_version" => ">= #{VERSION}"))
      end

      def test_raises_on_unsatisfied_host_version
        error = assert_raises(Error) { Manifest.new("/p", VALID.merge("host_version" => "> #{VERSION}")) }

        assert_match "requires inferno_suite_generator > #{VERSION}", error.message
      end
    end
  end
end
