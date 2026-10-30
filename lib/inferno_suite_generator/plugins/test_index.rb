# frozen_string_literal: true

module InfernoSuiteGenerator
  module Plugins
    # Finds a group's tests by what they are rather than by id, so a plugin can attach text or data to the
    # right test without rebuilding the host's test ids:
    #
    #   index = context.test_index(group)
    #   index.find("read")                                       # => "au_core_v200_patient_read_test"
    #   index.find("search", search_names: %w[patient code])     # parameter names in any order
    #   index.find("include", include_targets: ["Patient"])
    #   index.all("patch")                                       # every patch test, in group order
    #
    # The kind is the host generator's template type (Generator::GeneratorConstants::TEMPLATE_TYPES), or the
    # plugin id for a test a Plugins::TestGenerator added. Details by kind:
    #
    #   search, multiple_or_search, multiple_and_search, chain_search, provenance_revinclude_search
    #     search_names
    #   include   search_names, include_targets
    #   patch, update   option, the test_id_option from the config
    #
    # A test added without a kind, such as one from configs.generic.register_generators, is never found.
    class TestIndex
      def initialize(group_metadata)
        @group_metadata = group_metadata
      end

      # The id of the first test in group order that matches, or nil.
      def find(kind, **details)
        all(kind, **details).first
      end

      # The ids of the tests of this kind whose details include the given ones, in group order. Arrays
      # match in any order.
      def all(kind, **details)
        wanted = { kind:, **details }
        @group_metadata.tests.to_a.filter_map do |test|
          id = test[:id]
          id if matches?(@group_metadata.test_kind(id), wanted)
        end
      end

      private

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
