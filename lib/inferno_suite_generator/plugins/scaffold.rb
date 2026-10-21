# frozen_string_literal: true

require "erb"
require "fileutils"
require_relative "error"
require_relative "manifest"
require_relative "../version"

module InfernoSuiteGenerator
  module Plugins
    # Creates a new folder plugin from the templates in plugins/scaffold/: plugin.yml, the plugin class, an
    # extractor, a test, a README and an AGENTS.md. "__id__" in a template path becomes the plugin id.
    #
    #   InfernoSuiteGenerator::Plugins::Scaffold.new(id: "my_plugin", destination: "plugins/my_plugin").create
    class Scaffold
      TEMPLATE_DIR = File.join(__dir__, "scaffold")

      attr_reader :id, :destination

      def initialize(id:, destination:)
        raise Error, "Invalid plugin id #{id.inspect}, expected snake_case" unless Manifest::ID_FORMAT.match?(id)

        @id = id
        @destination = destination
      end

      def module_name
        id.split("_").map(&:capitalize).join
      end

      def host_version
        VERSION
      end

      # Returns the paths it wrote.
      def create
        raise Error, "#{destination} already exists" if File.exist?(destination)

        Dir.glob("**/*.erb", base: TEMPLATE_DIR).sort.map { |template| write(template) }
      end

      private

      def write(template)
        target = File.join(destination, template.delete_suffix(".erb").gsub("__id__", id))
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, ERB.new(File.read(File.join(TEMPLATE_DIR, template)), trim_mode: "-").result(binding))
        target
      end
    end
  end
end
