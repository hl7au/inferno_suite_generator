# frozen_string_literal: true

require "fhir_models"
require "uri"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # One x-fhir-query, parsed once.
    class FhirQuery
      CODE_PARAMS = %i[code category].freeze
      RESULT_PARAMS = %w[_sort _include _revinclude _count _elements _summary _total _contained _containedType].freeze
      PAIR = /(?:\{\{.*?\}\}|[^&])+/
      private_constant :RESULT_PARAMS, :PAIR

      def initialize(text)
        @text = text.to_s
        path, search = @text.split("?", 2)
        @segments = path.to_s.split("/")
        @type_index = @segments.rindex { |segment| FHIR::RESOURCES.include?(segment) }
        @pairs = search.to_s.scan(PAIR).map { |pair| decoded_pair(pair) }
      end

      def to_s
        @text
      end

      def resource_type
        @type_index ? @segments[@type_index] : @segments.last
      end

      def read?
        return false unless @type_index

        following = @segments[@type_index + 1]
        !following.nil? && !following.start_with?("_", "$") && @segments.none? { |segment| segment.start_with?("$") }
      end

      def search_params
        names = @pairs.map { |name, _value| name.split(":").first }
        [*compartment_param, *names].uniq - RESULT_PARAMS
      end

      def includes
        @pairs.filter_map { |name, value| value if own_include?(name, value) }
      end

      def other_includes
        @pairs.select { |name, value| name.start_with?("_include") && !own_include?(name, value) }
      end

      def codes
        CODE_PARAMS.to_h do |param|
          [param, @pairs.select { |name, _value| name == param.to_s }.flat_map { |_name, value| code_values(value) }]
        end
      end

      private

      def decoded_pair(pair)
        name, value = pair.split("=", 2)
        [decode(name.to_s), decode(value.to_s)]
      end

      def own_include?(name, value)
        name == "_include" && value.split(":").first == resource_type
      end

      def compartment_param
        compartment = @segments[@type_index - 2] if @type_index && @type_index >= 2
        compartment.downcase if FHIR::RESOURCES.include?(compartment)
      end

      def code_values(value)
        return [] if value.include?("{{")

        value.split(",").filter_map do |token|
          parts = token.split("|", 2)
          code = parts.last.to_s
          next if code.empty?

          system = parts.first if parts.size == 2
          { system: system.to_s.empty? ? nil : system, code: }
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
