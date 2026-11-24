# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # All placements of one run, and the one place that decides whether an element is checked:
    # by a group's own profile, or, for a source, by any group it fits (once per source and path).
    class Trace
      def initialize(placements)
        @placements = placements
        @profiles = Hash.new { |cache, group| cache[group] = CheckedElements.new(group) }
        @by_source = Hash.new { |cache, key| cache[key] = source_checks?(*key) }
        @labels = {}
      end

      def fitting(group) = @placements.select { |placement| placement.group.equal?(group) }

      # An include fits every group of its target type, but its include test lists it once.
      def listed(group)
        @placements.select { |placement| placement.listed_in?(group) }.uniq(&:source)
      end

      # The placements a group's summary names: those that fit it or that its tests list.
      def summarized(group)
        @placements.select { |placement| placement.named_in?(group) }
      end

      def by_group?(group, path) = @profiles[group].checks?(path)

      def by_source?(source, path) = @by_source[[source, path]]

      # Extensions are shown by the slice name any group the source fits gives them.
      def label(source, path) = @labels[[source, path]] ||= CheckedElements.label(path, source_slices(source))

      private

      # The first fitting group's slice name wins.
      def source_slices(source) = groups(source).map { |group| @profiles[group].slices }.reverse.reduce({}, :merge)

      def groups(source) = @placements.select { |placement| placement.source.equal?(source) }.map(&:group)

      def source_checks?(source, path) = groups(source).any? { |group| by_group?(group, path) }
    end
  end
end
