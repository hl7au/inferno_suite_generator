# frozen_string_literal: true

require "date"

module InfernoSuiteGenerator
  class Generator
    class GeneratorConfigKeeper
      # Provides methods for resolving dynamic values in the generator configuration
      module DynamicValueResolver
        TOKEN_PATTERN = /\$\{(Time\.now|DateTime\.now)\}/
        TOKEN_RESOLVERS = {
          "Time.now" => -> { Date.today.iso8601 },
          "DateTime.now" => -> { DateTime.now.strftime("%Y-%m-%dT%H:%M:%S%:z") }
        }.freeze

        # :reek:FeatureEnvy
        # :reek:TooManyStatements
        def resolve_dynamic_values(value)
          case value
          when String
            value.gsub(TOKEN_PATTERN) do
              token = Regexp.last_match(1)
              TOKEN_RESOLVERS[token]&.call if token
            end
          when Array then value.map { |element| resolve_dynamic_values(element) }
          else
            value
          end
        end
      end
    end
  end
end
