# frozen_string_literal: true

require_relative "../utils/generator_constants"

module InfernoSuiteGenerator
  class Generator
    # Finds a group's tests by kind (a GeneratorConstants::TEMPLATE_TYPES value) and recorded details, like
    # `find("search", search_names: %w[patient code])`. The generators record these in memory, so a test is found
    # only in the process that generated it, after it was generated, and never when it was added without a kind.
    class TestIndex
      Test = Data.define(:id, :kind, :details)

      KINDS = GeneratorConstants::TEMPLATE_TYPES.values.freeze

      def initialize(group_metadata)
        @group_metadata = group_metadata
      end

      # The first Test in group order of this kind whose details include the given ones, or nil. Arrays match
      # in any order.
      def find(kind, **details)
        raise ArgumentError, "Unknown test kind: #{kind}" unless KINDS.include?(kind)

        tests.find { |test| test.kind == kind && matches?(test.details, details) }
      end

      # Whether the group recorded any test with a kind.
      def any?
        tests.any?
      end

      private

      def tests
        @group_metadata.tests.to_a.filter_map do |test|
          id = test[:id]
          recorded = @group_metadata.test_kind(id)
          kind = recorded[:kind]
          Test.new(id:, kind:, details: recorded.except(:kind)) if kind
        end
      end

      def matches?(recorded, wanted)
        wanted.all? { |key, value| same?(recorded[key], value) }
      end

      # :reek:UtilityFunction
      def same?(recorded, value)
        return recorded.is_a?(Array) && recorded.sort == value.sort if value.is_a?(Array)

        recorded == value
      end
    end
  end
end
