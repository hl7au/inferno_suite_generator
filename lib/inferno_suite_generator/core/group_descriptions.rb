# frozen_string_literal: true

require_relative "../utils/naming"

module InfernoSuiteGenerator
  class Generator
    # Collects Markdown that GroupGenerator appends to group and test descriptions, keyed by group directory so any
    # GroupMetadata for a profile reaches the same group. Callers pass plain Markdown: it is escaped here because the
    # group template puts it inside a %( ... ) literal, where a backslash, parenthesis or #{ would break the file.
    class GroupDescriptions
      def self.escape(text)
        text.gsub(/[\\()]|#[{@$]/) { |match| "\\#{match}" }
      end

      def initialize
        @entries = {}
        @test_entries = {}
      end

      # Appends Markdown to the group's description. Ignores nil and blank text.
      def group(group_metadata, markdown)
        return if blank?(markdown)

        (@entries[key(group_metadata)] ||= []) << markdown
      end

      # Appends Markdown to the description of one of the group's tests, such as the id of a test from TestIndex.
      # Ignores nil and blank text. Raises ArgumentError when the group has no test with that id.
      def test(group_metadata, test_id, markdown)
        return if blank?(markdown)

        id = test_id.to_s
        unless group_metadata.tests.to_a.any? { |test| test[:id].to_s == id }
          raise ArgumentError,
                "Cannot add a description to test #{id}, which group #{group_metadata.name} does not have."
        end

        (@test_entries[[key(group_metadata), id]] ||= []) << markdown
      end

      # The group's Markdown in the order it was added, [] when there is none.
      def for(group_metadata)
        @entries.fetch(key(group_metadata)) { [] }
      end

      # The Markdown added to one of the group's tests, in the order it was added, [] when there is none.
      def for_test(group_metadata, test_id)
        @test_entries.fetch([key(group_metadata), test_id.to_s]) { [] }
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
        Naming.snake_case_for_profile(group_metadata)
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
