# frozen_string_literal: true

require_relative "../../utils/dynamic_value_resolver"

module InfernoSuiteGenerator
  class Generator
    class GeneratorConfigKeeper
      # Provides methods for resolving dynamic values in the generator configuration
      module DynamicValueResolver
        include InfernoSuiteGenerator::DynamicValueResolver

        TOKEN_PATTERN = InfernoSuiteGenerator::DynamicValueResolver::TOKEN_PATTERN
        TOKEN_RESOLVERS = InfernoSuiteGenerator::DynamicValueResolver::TOKEN_RESOLVERS
      end
    end
  end
end
