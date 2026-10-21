# frozen_string_literal: true

require_relative "base"
require_relative "context"
require_relative "error"

module InfernoSuiteGenerator
  module Plugins
    # A plugin ready to run: its manifest, an instance of its class and its options from the config.
    LoadedPlugin = Data.define(:manifest, :instance, :options) do
      # Requires the manifest's entrypoint and creates the class it names, checking the plugin contract.
      def self.build(manifest, options)
        require manifest.entrypoint_path
        new(manifest:, instance: instantiate(manifest), options:)
      rescue LoadError => e
        raise Error, "Plugin #{manifest.id.inspect} entrypoint could not be loaded: #{e.message}"
      end

      def self.instantiate(manifest)
        instance = plugin_class(manifest).new
        return instance if Base.implemented_by?(instance)

        raise Error, "Plugin #{manifest.id.inspect} class #{manifest.class_name} must define generate(context)"
      end

      def self.plugin_class(manifest)
        class_name = manifest.class_name
        Object.const_get(class_name)
      rescue NameError => e
        raise Error, "Plugin #{manifest.id.inspect} class #{class_name} is not defined: #{e.message}"
      end

      def id
        manifest.id
      end

      # host: the Context fields that come from the host, i.e. all but manifest, options and metadata.
      def generate(store, host)
        puts "Running plugin: #{id} #{manifest.version}"
        instance.generate(Context.new(manifest:, options:, metadata: store.for_plugin(id), **host))
      end
    end
  end
end
