# frozen_string_literal: true

require "fhir_models"
require "uri"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # Reads the type and search parameters of an x-fhir-query.
    module QuerySearch
      # Parameters that shape the result instead of selecting resources.
      RESULT_PARAMS = %w[_sort _include _revinclude _count _elements _summary _total _contained _containedType].freeze

      module_function

      # `{ resource_type:, read: }`. The type is the last path segment that names
      # a resource type, so `Patient/{{%patient.id}}` and the compartment search
      # `Patient/{{%patient.id}}/Observation?...` give `Patient` and
      # `Observation`. Without one it is the last segment. The query is a read,
      # which gives one resource instead of a Bundle, when an id follows the type.
      def target(query)
        segments = query.to_s.split("?", 2).first.to_s.split("/")
        index = segments.rindex { |segment| FHIR::RESOURCES.include?(segment) }
        return { resource_type: segments.last, read: false } unless index

        following = segments[index + 1]
        { resource_type: segments[index], read: !following.nil? && !following.start_with?("_") }
      end

      # The parameter names that select resources, without modifiers.
      def params(query)
        pairs(query).map { |name, _value| name.split(":").first }.uniq - RESULT_PARAMS
      end

      # The `_include` values, like `PractitionerRole:location`.
      def includes(query)
        pairs(query).filter_map { |name, value| value if name.split(":").first == "_include" && !value.empty? }
      end

      # `[name, value]` for each search parameter, decoded. A parameter without
      # `=` has the value `""`.
      def pairs(query)
        query.to_s.split("?", 2)[1].to_s.split("&").map do |pair|
          name, value = pair.split("=", 2)
          [decode(name.to_s), decode(value.to_s)]
        end
      end

      def decode(text)
        URI.decode_uri_component(text)
      rescue ArgumentError
        text
      end
    end
  end
end
