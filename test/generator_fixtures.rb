# frozen_string_literal: true

require "json"
require "tmpdir"
require "inferno_suite_generator/core/generator_config_keeper"
require "inferno_suite_generator/core/group_metadata"
require "inferno_suite_generator/core/ig_metadata"
require "inferno_suite_generator/utils/registry"

module InfernoSuiteGenerator
  # Helpers for tests that drive generators directly.
  module GeneratorFixtures
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

    def build_config_keeper(config = {})
      merged = default_config.merge(config) { |_section, default, given| default.merge(given) }
      Dir.mktmpdir do |dir|
        path = File.join(dir, "config.json")
        File.write(path, JSON.generate(merged))
        Generator::GeneratorConfigKeeper.new([path])
      end
    end

    def with_config_keeper(config = {})
      previous_config_keeper = Registry.get(:config_keeper)
      config_keeper = build_config_keeper(config)
      Registry.register(:config_keeper, config_keeper)
      yield config_keeper
    ensure
      Registry.register(:config_keeper, previous_config_keeper)
    end
  end
end
