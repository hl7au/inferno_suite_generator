# frozen_string_literal: true

require_relative "../utils/naming"

module InfernoSuiteGenerator
  module Plugins
    # Collects the Markdown plugins add to group descriptions. GroupGenerator appends it, after the built-in
    # description, when it writes each group file. Entries are keyed by group directory, so any GroupMetadata
    # for a profile reaches the same group, and keep the order they were added in: plugins in config order,
    # then each plugin's calls in order.
    #
    # Plugins pass plain Markdown and the host escapes it, because the group template puts the description
    # inside a %( ... ) literal: an unescaped backslash, parenthesis or #{, #@, #$ would change or break the
    # generated Ruby file.
    #
    # Nothing is written to disk: the text ends up only in the generated group files.
    class GroupDescriptions
      Entry = Data.define(:plugin_id, :markdown)

      # The view of the collector a plugin gets as context.descriptions, bound to that plugin's id.
      class Writer
        attr_reader :plugin_id

        def initialize(descriptions, plugin_id)
          @descriptions = descriptions
          @plugin_id = plugin_id
        end

        def group(group_metadata, markdown)
          @descriptions.add(group_metadata, plugin_id, markdown)
        end

        # Adds a hash of group metadata to that group's Markdown, such as one built from an Extractor result.
        def groups(markdown_by_group)
          markdown_by_group.each { |group_metadata, markdown| group(group_metadata, markdown) }
        end
      end

      def self.escape(text)
        text.gsub(/[\\()]|#[{@$]/) { |match| "\\#{match}" }
      end

      def initialize
        @entries = Hash.new { |entries, key| entries[key] = [] }
      end

      def for_plugin(plugin_id)
        Writer.new(self, plugin_id)
      end

      # Ignores nil and blank text.
      def add(group_metadata, plugin_id, markdown)
        return if markdown.to_s.strip.empty?

        @entries[Generator::Naming.snake_case_for_profile(group_metadata)] << Entry.new(plugin_id:, markdown:)
      end

      # The group's Markdown in the order it was added, [] when there is none.
      def for(group_metadata)
        @entries.fetch(Generator::Naming.snake_case_for_profile(group_metadata)) { [] }.map(&:markdown)
      end

      # The group's Markdown, escaped for the group template and joined by blank lines, or nil when there is none.
      def section(group_metadata)
        texts = self.for(group_metadata)
        return if texts.empty?

        texts.map { |text| self.class.escape(text) }.join("\n\n")
      end
    end
  end
end
