# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # The steps of a chain on a search's Bundle: entry, entry picks, resource, then what it reads on the
    # resource. Only entry … resource reads elements, so %q.total and %q.entry.count() read none.
    class Entries
      PICKS = %w[where first last tail skip take single].freeze
      IS_TYPE = /\Aresource\.is\((\w+)\)\z/

      def self.member?(step, name) = step.kind == :member && step.name == name

      def self.pick?(step) = step.kind == :index || step.function?(PICKS)

      # T for where(resource is T) or where(resource.is(T)).
      def self.picked_type(step)
        params = step.params
        condition_type(params.first) if step.name == "where" && params.one?
      end

      def self.condition_type(condition)
        left, right = condition.fetch("children", [])
        return right["text"] if condition["type"] == "TypeExpression" && left["text"] == "resource"

        condition["text"].to_s[IS_TYPE, 1]
      end

      # The entry picks after a leading entry, or nil when the chain does not start at entry.
      def self.picks(steps)
        entry, *rest = steps
        rest.take_while { |step| pick?(step) } if entry && member?(entry, "entry")
      end

      # T for ofType(T).
      def self.of_type(step)
        params = step.params
        params.first["text"] if step.function?(["ofType"]) && params.size == 1
      end

      def initialize(steps)
        @picks = Entries.picks(steps)
        resource, *read = steps.drop(@picks.to_a.size + 1)
        @resource = resource && Entries.member?(resource, "resource")
        @of_type = Entries.of_type(read.first) if @resource && read.any?
        @read = read.drop(@of_type ? 1 : 0)
      end

      # The paths read on resources of the given type, or nil when the chain picks another type.
      def paths_for(type)
        return [] unless @picks
        return unless [nil, type].include?(picked_type)

        @resource ? Chain::Reading.new.paths(@read) : []
      end

      private

      # The last type a where(resource is T) pick or resource.ofType(T) gives.
      def picked_type = [*@picks.filter_map { |step| Entries.picked_type(step) }, *@of_type].last
    end
  end
end
