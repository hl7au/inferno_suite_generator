# frozen_string_literal: true

require "date"

module InfernoSuiteGenerator
  # Provides methods for resolving dynamic values in the generator configuration
  module DynamicValueResolver
    TOKEN_PATTERN = /\$\{([^}]+)\}/
    TOKEN_RESOLVERS = {
      "Time.now" => -> { Date.today.iso8601 },
      "DateTime.now" => -> { DateTime.now.strftime("%Y-%m-%dT%H:%M:%S%:z") }
    }.freeze

    # :reek:FeatureEnvy
    # :reek:TooManyStatements
    def resolve_dynamic_values(value) # rubocop:disable Metrics/MethodLength
      case value
      when String
        value.gsub(TOKEN_PATTERN) do
          key = Regexp.last_match(1)
          resolver = TOKEN_RESOLVERS[key]
          unless resolver
            warn "[DynamicValueResolver] Unknown token: ${#{key}} — leaving unchanged"
            next Regexp.last_match(0)
          end
          resolver.call
        end
      when Array then value.map { |element| resolve_dynamic_values(element) }
      when Hash then value.transform_values { |val| resolve_dynamic_values(val) }
      else
        value
      end
    end
  end
end
