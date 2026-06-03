# frozen_string_literal: true

require_relative "../../utils/dynamic_value_resolver"

module InfernoSuiteGenerator
  class Generator
    class GeneratorConfigKeeper
      # Provides methods for resolving dynamic values in the generator configuration
      module DynamicValueResolver
        include InfernoSuiteGenerator::DynamicValueResolver
      end
    end
  end
end
