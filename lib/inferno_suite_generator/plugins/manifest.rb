# frozen_string_literal: true

require "yaml"
require_relative "error"
require_relative "../version"

module InfernoSuiteGenerator
  module Plugins
    # The plugin.yml file every plugin, gem or folder, keeps at its root.
    #
    #   id: read                          # unique, snake_case; the key in config and in plugins.yml
    #   name: Read tests
    #   version: 0.1.0
    #   description: Generates a read test for every profile with a read interaction
    #   entrypoint: lib/read.rb           # required before the plugin runs, relative to the root
    #   class: InfernoSuitePlugins::Read::Plugin
    #   host_version: ">= 0.1.0"          # optional, checked against InfernoSuiteGenerator::VERSION
    #   templates: templates              # optional, defaults to "templates"
    #   runtime: runtime                  # optional, defaults to "runtime"
    class Manifest
      FILE_NAME = "plugin.yml"
      ID_FORMAT = /\A[a-z][a-z0-9_]*\z/
      REQUIRED_KEYS = %w[id name version entrypoint class].freeze

      attr_reader :root, :data

      def self.load(root)
        path = File.join(root, FILE_NAME)
        raise Error, "Plugin manifest not found: #{path}" unless File.exist?(path)

        new(root, YAML.safe_load_file(path) || {})
      end

      def initialize(root, data)
        @root = File.expand_path(root)
        @data = data
        validate
      end

      def id
        data["id"]
      end

      def name
        data["name"]
      end

      def version
        data["version"].to_s
      end

      def class_name
        data["class"]
      end

      def entrypoint_path
        File.expand_path(data["entrypoint"], root)
      end

      def templates_dir
        File.expand_path(data["templates"] || "templates", root)
      end

      def runtime_dir
        File.expand_path(data["runtime"] || "runtime", root)
      end

      private

      def validate
        validate_required_keys
        fail_with("has an invalid id #{id.inspect}, expected snake_case") unless ID_FORMAT.match?(id.to_s)
        validate_host_version
      end

      def validate_required_keys
        missing = REQUIRED_KEYS.select { |key| data[key].to_s.strip.empty? }
        fail_with("is missing #{missing.join(", ")}") if missing.any?
      end

      def validate_host_version
        requirement = data["host_version"]
        return unless requirement
        return if Gem::Requirement.new(*Array(requirement)).satisfied_by?(Gem::Version.new(VERSION))

        fail_with("requires inferno_suite_generator #{requirement}, but #{VERSION} is installed")
      end

      def fail_with(message)
        raise Error, "Plugin manifest #{File.join(root, FILE_NAME)} #{message}"
      end
    end
  end
end
