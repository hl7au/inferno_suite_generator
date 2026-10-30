# frozen_string_literal: true

require "yaml"

module InfernoSuiteGenerator
  module Plugins
    # Reads one plugin's section of a plugins.yml file from inside a generated test, at Inferno run time:
    #
    #   def self.plugin_metadata
    #     @plugin_metadata ||= InfernoSuiteGenerator::Plugins::RuntimeMetadata.load(__dir__, 'read')
    #   end
    module RuntimeMetadata
      FILE_NAME = "plugins.yml"

      def self.load(directory, plugin_id)
        path = File.join(directory, FILE_NAME)
        return {} unless File.exist?(path)

        content = YAML.safe_load_file(path, aliases: true, permitted_classes: [Symbol]) || {}
        content[plugin_id.to_s] || {}
      end
    end
  end
end
