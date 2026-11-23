# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # All placements of one run, and the one place that decides whether an element is checked:
    # by a group's own profile, or, for a source, by any group it fits (once per source and path).
    class Trace
      def initialize(placements)
        @placements = placements
        @by_group = placements.group_by(&:group)
        @profiles = Hash.new { |cache, group| cache[group] = CheckedElements.new(group) }
        @by_source = Hash.new { |cache, key| cache[key] = source_checks?(*key) }
      end

      def fitting(group) = @by_group.fetch(group, [])

      def listed(group)
        @placements.select { |placement| placement.listed_in?(group) }
      end

      def by_group?(group, path) = @profiles[group].checks?(path)

      def by_source?(source, path) = @by_source[[source, path]]

      private

      def source_checks?(source, path)
        @placements.any? { |placement| placement.source.equal?(source) && by_group?(placement.group, path) }
      end
    end
  end
end
