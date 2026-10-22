# frozen_string_literal: true

require "fileutils"
require "yaml"
require_relative "../utils/naming"

module InfernoSuiteGenerator
  module Plugins
    # Collects plugin metadata and writes it to plugins.yml files: one in the suite directory and one in each
    # group directory, next to the host's metadata.yml (which plugins never touch). Every file is a hash keyed
    # by plugin id, so many plugins share one file:
    #
    #   read:
    #     interaction:
    #       code: read
    #       expectation: SHALL
    #   another_plugin:
    #     ...
    #
    # Keys are written as strings. Writing twice for the same plugin and directory deep-merges the data:
    # nested hashes merge, arrays are appended to (so each generated test can add itself to "tests"), and
    # any other value is replaced.
    class MetadataStore
      FILE_NAME = "plugins.yml"

      # The view of the store a plugin gets as context.metadata, bound to that plugin's id.
      class Writer
        attr_reader :plugin_id

        def initialize(store, plugin_id)
          @store = store
          @plugin_id = plugin_id
        end

        def suite(data)
          @store.write(@store.suite_directory, plugin_id, data)
        end

        def group(group_metadata, data)
          @store.write(@store.group_directory(group_metadata), plugin_id, data)
        end

        # Writes the result of an Extractor: a hash of group metadata to that group's data.
        def groups(data_by_group)
          data_by_group.each { |group_metadata, data| group(group_metadata, data) }
        end
      end

      attr_reader :suite_directory

      def initialize(suite_directory)
        @suite_directory = suite_directory
        @files = Hash.new { |files, path| files[path] = {} }
      end

      def for_plugin(plugin_id)
        Writer.new(self, plugin_id)
      end

      def group_directory(group_metadata)
        File.join(suite_directory, Generator::Naming.snake_case_for_profile(group_metadata))
      end

      def write(directory, plugin_id, data)
        content = @files[File.join(directory, FILE_NAME)]
        content[plugin_id] = deep_merge(content[plugin_id] || {}, stringify(data))
      end

      def flush
        @files.each do |path, content|
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, YAML.dump(content))
        end
      end

      private

      def stringify(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, stringify(item)] }
        when Array then value.map { |element| stringify(element) }
        else value
        end
      end

      def deep_merge(base, other)
        base.merge(other) do |_key, old_value, new_value|
          case [old_value, new_value]
          in [Hash, Hash] then deep_merge(old_value, new_value)
          in [Array, Array] then old_value + new_value
          else new_value
          end
        end
      end
    end
  end
end
