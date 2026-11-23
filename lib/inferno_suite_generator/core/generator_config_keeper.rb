# frozen_string_literal: true

require "json"
require "deep_merge"
require_relative "config/getters"
require_relative "config/extractors"
require_relative "config/generators"
require_relative "config/constants"
require_relative "config/utils"

module InfernoSuiteGenerator
  class Generator
    # Manages configuration for the InfernoSuiteGenerator
    #
    # This class is responsible for loading, validating, and providing access to
    # configuration settings used throughout the test suite generation process.
    class GeneratorConfigKeeper
      include Getters
      include Extractors
      include Generators
      include Constants
      include Utils

      attr_reader :config, :version, :config_file_paths

      def initialize(config_file_paths)
        @config_file_paths = config_file_paths
        @cache = {}
        load_config
        validate_config
      end

      def reload
        @cache = {}
        load_config
        validate_config
        @config
      end

      def suite_module_name
        "#{module_name_prefix}TestKit"
      end

      def module_directory
        "#{test_id_prefix}_test_kit"
      end

      def module_name_prefix
        title.delete(" ")
      end

      def test_id_prefix
        title.downcase.tr(" ", "_")
      end

      def result_folder
        "./lib/#{module_directory}/generated/"
      end

      def related_result_folder
        "/lib/#{module_directory}/generated/"
      end

      def ig_deps_path
        "lib/#{module_directory}/igs/"
      end

      def main_file_path
        "lib/#{module_directory}.rb"
      end

      private

      def load_config
        all_configs_exists = @config_file_paths.map { |path_str| File.exist?(path_str) }.all?
        raise ArgumentError, "Configuration file not found: #{@config_file_paths.join(", ")}" unless all_configs_exists

        begin
          prepare_config_hash
          @version = get("ig.version", [])
        rescue JSON::ParserError => e
          raise ArgumentError, "Invalid JSON in configuration file: #{e.message}"
        end
      end

      def prepare_config_hash
        config_hash = {}
        @config_file_paths.each do |config_file_path|
          config_hash.deep_merge!(JSON.parse(File.read(config_file_path)))
        end
        @config = config_hash
      end

      def validate_config
        required_sections = %w[ig suite configs]

        required_sections.each do |section|
          raise ArgumentError, "Missing required configuration section: #{section}" unless @config.key?(section)
        end
      end
    end
  end
end
