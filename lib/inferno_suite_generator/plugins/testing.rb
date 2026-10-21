# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../core/generator_config_keeper"
require_relative "../core/group_metadata"
require_relative "../core/ig_metadata"
require_relative "../utils/registry"
require_relative "group_descriptions"
require_relative "loader"
require_relative "metadata_store"
require_relative "runtime_metadata"

module InfernoSuiteGenerator
  module Plugins
    # Helpers for a plugin's own tests: build small IG metadata by hand, load the plugin through the real
    # Loader and run it into a temporary directory, then inspect the files and plugins.yml it wrote, and the
    # group description text it added.
    #
    #   include InfernoSuiteGenerator::Plugins::Testing
    #
    #   group = build_group_metadata(interactions: [{ code: "read", expectation: "SHALL" }])
    #   descriptions = run_plugin(PLUGIN_ROOT, ig_metadata: build_ig_metadata(groups: [group]), base_output_dir: dir)
    #   plugin_metadata(File.join(dir, "patient"), "read")  # => { "interaction" => ... }
    #   descriptions.for(group)                             # => ["## Read", ...]
    #
    # The fixture builders need no instance state, so they are utility functions on purpose.
    # :reek:UtilityFunction
    module Testing
      # Built fresh on every call: the host mutates group metadata (add_test) and config hashes in place.
      def default_config
        {
          "ig" => { "id" => "example.ig", "version" => "1.0.0" },
          "suite" => { "title" => "Example" },
          "configs" => {}
        }
      end

      def default_group_attributes
        {
          name: "example_patient", class_name: "ExamplePatientSequence", version: "v1.0.0",
          reformatted_version: "v100", resource: "Patient",
          profile_url: "http://example.org/StructureDefinition/example-patient", profile_name: "Example Patient",
          profile_version: "1.0.0", title: "Example Patient", short_description: "", interactions: [],
          operations: [], searches: [], search_definitions: {}, include_params: [], revincludes: [],
          required_concepts: [], must_supports: {}, mandatory_elements: [], bindings: [], references: [], tests: []
        }
      end

      def build_group_metadata(**attributes)
        Generator::GroupMetadata.new(default_group_attributes.merge(attributes))
      end

      def build_ig_metadata(groups:, **attributes)
        defaults = {
          ig_id: "example.ig", ig_title: "Example IG", ig_version: "1.0.0", ig_test_id_prefix: "example",
          ig_module_name_prefix: "Example"
        }
        Generator::IGMetadata.new.tap do |ig_metadata|
          defaults.merge(attributes, groups:).each { |name, value| ig_metadata.public_send(:"#{name}=", value) }
        end
      end

      # Each top-level section of config is merged into default_config, the minimum GeneratorConfigKeeper
      # accepts.
      def build_config_keeper(config = {})
        Dir.mktmpdir do |dir|
          path = File.join(dir, "config.json")
          File.write(path, JSON.generate(merge_into_default_config(config)))
          Generator::GeneratorConfigKeeper.new([path])
        end
      end

      def merge_into_default_config(config)
        default_config.merge(config) { |_section, default, given| default.merge(given) }
      end

      # Registers a config keeper built from config for the duration of the block, as host helpers such as
      # Naming read it from Registry, and yields it.
      def with_config_keeper(config = {})
        previous_config_keeper = Registry.get(:config_keeper)
        config_keeper = build_config_keeper(config)
        Registry.register(:config_keeper, config_keeper)
        yield config_keeper
      ensure
        Registry.register(:config_keeper, previous_config_keeper)
      end

      # Loads the plugin at plugin_root the way the host does, runs it and writes its plugins.yml files. host
      # takes the Context fields the host provides: ig_metadata and base_output_dir, optionally ig_resources
      # and ig_demodata. Returns the GroupDescriptions the plugin added to.
      # :reek:LongParameterList
      # :reek:TooManyStatements
      def run_plugin(plugin_root, options: {}, config: {}, **host)
        plugin = load_plugin(plugin_root, options)
        store = MetadataStore.new(host.fetch(:base_output_dir))
        descriptions = GroupDescriptions.new
        with_config_keeper(config) do |config_keeper|
          plugin.generate(store, { ig_resources: nil, ig_demodata: nil, **host, config: config_keeper }, descriptions:)
        end
        store.flush
        descriptions
      end

      def load_plugin(plugin_root, options = {})
        id = Manifest.load(plugin_root).id
        Loader.new({ id => { "path" => plugin_root, "options" => options } }).load.first
      end

      def plugin_metadata(directory, plugin_id)
        RuntimeMetadata.load(directory, plugin_id)
      end
    end
  end
end
