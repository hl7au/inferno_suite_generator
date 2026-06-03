# frozen_string_literal: true

require "date"

module InfernoSuiteGenerator
  # Provides methods for resolving dynamic values in the generator configuration
  module DynamicValueResolver
    TOKEN_PATTERN = /\$\{(Time\.now|DateTime\.now)\}/
    TOKEN_RESOLVERS = {
      "Time.now" => -> { Date.today.iso8601 },
      "DateTime.now" => -> { DateTime.now.strftime("%Y-%m-%dT%H:%M:%S%:z") }
    }.freeze

    def resolve_dynamic_values(value)
      case value
      when String
        value.gsub(TOKEN_PATTERN) { TOKEN_RESOLVERS.fetch(Regexp.last_match(1)).call }
      when Array then value.map { |element| resolve_dynamic_values(element) }
      when Hash then value.transform_values { |v| resolve_dynamic_values(v) }
      else
        value
      end
    end
  end
end
