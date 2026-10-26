# frozen_string_literal: true

require_relative "usage_section"

module InfernoSuitePlugins
  module QuestionnaireUsageTracing
    # Collects the entries routed to each test and adds one "Used in
    # questionnaires" section per test to its description. An entry several
    # groups share, like an `_include` that links to two profiles of the same
    # type, is listed once per test, against the first group it came from.
    class TestSections
      READS = "A form can pre-fill an item only if the server returns the elements the item reads. Elements " \
              "marked #{UsageSection::NOT_CHECKED} are neither Must Support nor required by the profile, so this " \
              "group's tests do not check them.".freeze

      def initialize(context)
        @context = context
        @tests = {}
      end

      # Adds the entry of `group` to the test of the Router::Destination.
      def add(destination, entry, group)
        test = (@tests[destination.test_id] ||= { destination:, entries: [] })
        test[:entries] << [entry, group] unless test[:entries].any? { |(added, _)| added.equal?(entry) }
      end

      def write
        @tests.each_value { |test| write_test(test[:destination], test[:entries]) }
      end

      private

      def write_test(destination, entries)
        group = entries.first.last
        section = UsageSection.new(entries.map(&:first), group, intro: intro(destination.kind, group.resource))
        @context.descriptions.test(destination.group, destination.test_id, section.markdown) unless section.empty?
      end

      # :reek:UtilityFunction
      def intro(kind, resource)
        case kind
        when "read"
          "These questionnaires in the IG read #{resource} resources as this test does: by id, or as the " \
          "resource a form is opened for. #{READS}"
        when "search" then "These questionnaires in the IG make this search. #{READS}"
        when "include"
          "These questionnaires in the IG fetch #{resource} resources through this search's _include. #{READS}"
        when "create" then "These questionnaires in the IG create #{resource} resources from their answers."
        else "These questionnaires in the IG update existing #{resource} resources from their answers."
        end
      end
    end
  end
end
