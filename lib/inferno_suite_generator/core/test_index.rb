# frozen_string_literal: true

require_relative "../utils/generator_constants"

module InfernoSuiteGenerator
  class Generator
    # Finds a group's tests by what they are rather than by id, so code can attach text or data to the right
    # test without rebuilding test ids:
    #
    #   index = TestIndex.new(group)
    #   index.find("read").id                                    # => "au_core_v200_patient_read_test"
    #   index.find("search", search_names: %w[patient code])     # parameter names in any order
    #   index.find("include", include_targets: ["Patient"])
    #
    # The kind is the generator's template type (GeneratorConstants::TEMPLATE_TYPES), and any other kind raises
    # ArgumentError. Details by kind:
    #
    #   search, multiple_or_search, multiple_and_search, chain_search, provenance_revinclude_search
    #     search_names
    #   include   search_names, include_targets
    #   update    option, "update" or "update_new"
    #
    # The generators record these in memory, on the group, so they exist only in the process that ran the
    # generators and only after they ran. A test added without a kind, such as one from
    # configs.generic.register_generators, is never found.
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
