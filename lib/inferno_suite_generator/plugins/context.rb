# frozen_string_literal: true

require "fileutils"

module InfernoSuiteGenerator
  module Plugins
    # The input of Plugin#generate. Everything the host has built by the time plugins run:
    #
    #   manifest        - the plugin's own Manifest (id, version, templates_dir, ...)
    #   options         - the "options" hash from the plugin's entry in the config, {} when absent
    #   ig_resources    - Generator::IGResources, every loaded IG artifact
    #   ig_metadata     - Generator::IGMetadata, the same object the host writes to metadata.yml
    #   ig_demodata     - Generator::IGDemodata, the same object the host writes to demodata.yml
    #   base_output_dir - the generated suite directory, e.g. lib/au_core_test_kit/generated/2.0.0
    #   config          - Generator::GeneratorConfigKeeper, the merged generator config
    #   metadata        - MetadataStore::Writer bound to this plugin, for plugins.yml files
    Context = Data.define(
      :manifest, :options, :ig_resources, :ig_metadata, :ig_demodata, :base_output_dir, :config, :metadata
    ) do
      def plugin_id
        manifest.id
      end

      # Groups the host generates tests for: the IG groups minus those excluded by skip / skip_generation.
      def groups
        ig_metadata.groups.reject { |group| config.exclude_resource?(group.profile_url, group.resource) }
      end

      def template_path(file_name)
        File.join(manifest.templates_dir, file_name)
      end

      # Where install_runtime puts the plugin's runtime files. Generated tests in a group directory reach
      # them with require_relative "../plugins/<plugin id>/<file>".
      def runtime_output_dir
        File.join(base_output_dir, "plugins", plugin_id)
      end

      # Copies the plugin's runtime directory (test modules, helpers, assets its generated tests need at
      # Inferno run time) into the generated suite, so a folder plugin's suite needs nothing outside it.
      def install_runtime(source_dir = manifest.runtime_dir)
        raise Error, "Runtime directory not found for plugin #{plugin_id}: #{source_dir}" unless Dir.exist?(source_dir)

        FileUtils.mkdir_p(runtime_output_dir)
        FileUtils.cp_r(File.join(source_dir, "."), runtime_output_dir)
        runtime_output_dir
      end
    end
  end
end
