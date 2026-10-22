# frozen_string_literal: true

require_relative "error"
require_relative "loaded_plugin"
require_relative "manifest"

module InfernoSuiteGenerator
  module Plugins
    # Turns the "plugins" config section into LoadedPlugins. The section is keyed by plugin id, which must
    # match the id in the plugin's plugin.yml, and each entry names exactly one source:
    #
    #   "plugins": {
    #     "core":   { "builtin": "core" },                            # <gem root>/plugins/core
    #     "local":  { "path": "plugins/local", "options": { ... } },  # a folder, relative to the working dir
    #     "shared": { "gem": "isg_shared_plugin" },                   # an installed gem's root
    #     "off":    { "path": "plugins/off", "enabled": false }       # skipped
    #   }
    #
    # Plugins run in the order they appear in the config.
    class Loader
      SOURCES = %w[path gem builtin].freeze
      BUILTIN_ROOT = File.expand_path("../../../plugins", __dir__)

      # One entry of the "plugins" config section.
      Entry = Data.define(:id, :settings) do
        def enabled?
          settings["enabled"] != false
        end

        def options
          settings.fetch("options") { {} }
        end

        def load_plugin(base_dir)
          manifest = Manifest.load(root(base_dir))
          check(manifest)
          LoadedPlugin.build(manifest, options)
        end

        private

        def root(base_dir)
          source, value = source_setting
          case source
          when "path" then File.expand_path(value, base_dir)
          when "gem" then gem_root(value)
          else File.join(BUILTIN_ROOT, value)
          end
        end

        def check(manifest)
          declared_id = manifest.id
          return if declared_id == id

          raise Error, "Plugin #{id.inspect} is configured, but its plugin.yml says id #{declared_id.inspect}"
        end

        def source_setting
          given = settings.slice(*SOURCES)
          return given.first if given.one?

          raise Error, "Plugin #{id.inspect} must set exactly one of #{SOURCES.join(", ")}"
        end

        def gem_root(gem_name)
          Gem::Specification.find_by_name(gem_name).gem_dir
        rescue Gem::MissingSpecError
          raise Error, "Plugin #{id.inspect} names gem #{gem_name.inspect}, which is not installed"
        end
      end

      def initialize(entries, base_dir: Dir.pwd)
        @entries = entries.map { |id, settings| Entry.new(id:, settings: settings || {}) }
        @base_dir = base_dir
      end

      def load
        @entries.select(&:enabled?).map { |entry| entry.load_plugin(@base_dir) }
      end
    end
  end
end
