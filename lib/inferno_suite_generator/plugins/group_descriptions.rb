# frozen_string_literal: true

require_relative "error"
require_relative "../utils/naming"

module InfernoSuiteGenerator
  module Plugins
    # Collects the Markdown plugins add to group descriptions and to the descriptions of a group's tests.
    # GroupGenerator appends it when it writes each group file: group text after the built-in group
    # description, test text after the test's own description, in the group's `test from:` block for that
    # test. Entries are keyed by group directory, so any GroupMetadata for a profile reaches the same group,
    # and keep the order they were added in: plugins in config order, then each plugin's calls in order.
    #
    # Plugins pass plain Markdown and the host escapes it, because the group template puts it inside a
    # %( ... ) literal: an unescaped backslash, parenthesis or #{, #@, #$ would change or break the generated
    # Ruby file.
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

        # Appends Markdown to the description of one of the group's tests, such as an id from
        # context.test_index(group). Raises Plugins::Error when the group has no test with that id.
        def test(group_metadata, test_id, markdown)
          @descriptions.add_to_test(group_metadata, test_id, plugin_id, markdown)
        end
      end

      def self.escape(text)
        text.gsub(/[\\()]|#[{@$]/) { |match| "\\#{match}" }
      end

      def initialize
        @entries = {}
        @test_entries = {}
      end

      def for_plugin(plugin_id)
        Writer.new(self, plugin_id)
      end

      # Ignores nil and blank text.
      def add(group_metadata, plugin_id, markdown)
        return if blank?(markdown)

        (@entries[key(group_metadata)] ||= []) << Entry.new(plugin_id:, markdown:)
      end

      # Ignores nil and blank text. Raises Plugins::Error when the group has no test with that id.
      # :reek:LongParameterList
      def add_to_test(group_metadata, test_id, plugin_id, markdown)
        return if blank?(markdown)

        id = test_id.to_s
        unless group_metadata.tests.to_a.any? { |test| test[:id].to_s == id }
          raise Error, "Plugin #{plugin_id} adds a description to test #{id}, which group " \
                       "#{group_metadata.name} does not have."
        end

        (@test_entries[[key(group_metadata), id]] ||= []) << Entry.new(plugin_id:, markdown:)
      end

      # The group's Markdown in the order it was added, [] when there is none.
      def for(group_metadata)
        @entries.fetch(key(group_metadata)) { [] }.map(&:markdown)
      end

      # The Markdown added to one of the group's tests, in the order it was added, [] when there is none.
      def for_test(group_metadata, test_id)
        @test_entries.fetch([key(group_metadata), test_id.to_s]) { [] }.map(&:markdown)
      end

      # The group's Markdown, escaped for the group template and joined by blank lines, or nil when there is none.
      def section(group_metadata)
        join(self.for(group_metadata))
      end

      # The same as section, for one of the group's tests.
      def test_section(group_metadata, test_id)
        join(for_test(group_metadata, test_id))
      end

      private

      # :reek:UtilityFunction
      def key(group_metadata)
        Generator::Naming.snake_case_for_profile(group_metadata)
      end

      # :reek:UtilityFunction
      def blank?(markdown)
        markdown.to_s.strip.empty?
      end

      def join(texts)
        return if texts.empty?

        texts.map { |text| self.class.escape(text) }.join("\n\n")
      end
    end
  end
end
