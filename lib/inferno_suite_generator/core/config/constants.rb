# frozen_string_literal: true

module InfernoSuiteGenerator
  class Generator
    class GeneratorConfigKeeper
      # Defines constant values used across the configuration system
      module Constants
        # @type var empty_array: Array[untyped]
        empty_array = []
        EMPTY_ARRAY = empty_array.freeze

        # @type var empty_hash: Hash[untyped, untyped]
        empty_hash = {}
        EMPTY_HASH = empty_hash.freeze

        # @type var empty_mutable_hash: Hash[untyped, untyped]
        empty_mutable_hash = {}
        EMPTY_MUTABLE_HASH = empty_mutable_hash
      end
    end
  end
end
