# frozen_string_literal: true

require "active_support/all"
require "fhir_models"
require "pathname"
require "rubygems/package"
require "zlib"
require "json"
require_relative "ig_resources"
require_relative "generator_config_keeper"
require_relative "../utils/registry"

module InfernoSuiteGenerator
  class Generator
    class IGLoader
      attr_accessor :ig_deps_path, :config

      def initialize(ig_deps_path)
        self.ig_deps_path = ig_deps_path
        self.config = Registry.get(:config_keeper)
      end

      def ig_resources
        @ig_resources ||= IGResources.new
      end

      def load
        load_ig
      end

      def load_ig
        if config.respond_to?(:package_archive_path) && config.package_archive_path
          process_package_archive(config.package_archive_path)
        end

        json_files = Dir.glob(File.join(Dir.pwd, config.ig_deps_path, "*.json"))
        json_files.reject! { |file| file.end_with?(".openapi.json") }

        if config.respond_to?(:extra_json_paths) && config.extra_json_paths.is_a?(Array)
          config.extra_json_paths.each do |extra_path|
            full_path = extra_path.start_with?("/") ? extra_path : File.join(Dir.pwd, extra_path)
            json_files << full_path if File.exist?(full_path) && !full_path.end_with?(".openapi.json")
          end
        end

        json_files.each do |file_path|
          puts "Loading JSON file: #{file_path}"
          file_content = File.read(file_path)

          begin
            json = JSON.parse(file_content)
            next unless json.is_a?(Hash) && json["resourceType"]

            bundle = FHIR.from_contents(file_content)
            ig_resources.add(bundle)
            bundle.entry.each_with_index do |entry, index|
              if entry.resource.resourceType == "CapabilityStatement" && config.cs_profile_url != entry.resource.url
                next
              end

              ig_resources.add(entry.resource, json.dig("entry", index, "resource"))
            end
          rescue JSON::ParserError => e
            puts "Error parsing JSON file #{file_path}: #{e.message}"
          end
        end
        ig_resources
      end

      def process_package_archive(archive_path)
        full_path = archive_path.start_with?("/") ? archive_path : File.join(Dir.pwd, archive_path)
        return unless File.exist?(full_path)

        resources = []

        begin
          Zlib::GzipReader.open(full_path) do |gz|
            Gem::Package::TarReader.new(gz) do |tar|
              tar.each do |entry|
                next unless entry.file? && entry.full_name.end_with?(".json")
                next if entry.full_name.end_with?(".openapi.json")

                begin
                  content = entry.read
                  json = JSON.parse(content)

                  next unless json.is_a?(Hash) && json["resourceType"]

                  resource = FHIR.from_contents(content)
                  resources << resource

                  ig_resources.add(resource, json)
                rescue StandardError => e
                  puts "Error processing #{entry.full_name}: #{e.message}"
                end
              end
            end
          end
        rescue Zlib::GzipFile::Error => e
          puts "Error: The file at #{archive_path} is not a valid gzip file. Please ensure it is a valid .tar.gz or .tgz archive."
          puts "Error details: #{e.message}"
        rescue Gem::Package::TarInvalidError => e
          puts "Error: The file at #{archive_path} is not a valid tar archive. Please ensure it is a valid .tar.gz or .tgz archive."
          puts "Error details: #{e.message}"
        rescue StandardError => e
          puts "Error processing archive at #{archive_path}: #{e.message}"
        end

        return unless resources.any?

        bundle_entries = resources.map do |resource|
          FHIR::Bundle::Entry.new(
            resource: resource,
            fullUrl: resource.respond_to?(:url) ? resource.url : nil
          )
        end

        bundle = FHIR::Bundle.new(
          type: "collection",
          entry: bundle_entries
        )

        temp_bundle_path = File.join(Dir.pwd, "package_archive_bundle.json")
        File.write(temp_bundle_path, bundle.to_json)
      end
    end
  end
end
