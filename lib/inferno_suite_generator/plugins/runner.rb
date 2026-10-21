# frozen_string_literal: true

require_relative "metadata_store"

module InfernoSuiteGenerator
  module Plugins
    # Runs loaded plugins, in config order, once the host has generated all its built-in tests and before it
    # builds groups and suites, so the tests plugins register end up in the generated groups. Then writes
    # every plugins.yml file.
    class Runner
      attr_reader :plugins

      def initialize(plugins = [])
        @plugins = plugins
      end

      # Whether a plugin with this id is enabled. The host uses it to skip a built-in generator that a plugin
      # replaces, such as the built-in read tests when the read plugin is on.
      def plugin?(id)
        plugins.any? { |plugin| plugin.id == id }
      end

      # host: the Context fields the host provides: ig_resources, ig_metadata, ig_demodata, base_output_dir
      # and config.
      def run(**host)
        return if plugins.empty?

        store = MetadataStore.new(host.fetch(:base_output_dir))
        plugins.each { |plugin| plugin.generate(store, host) }
        store.flush
      end
    end
  end
end
