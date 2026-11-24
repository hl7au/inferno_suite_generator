# frozen_string_literal: true

require "uri"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # One application/x-fhir-query variable on the root or an item: a read of one resource by id, or a search
    # whose items read its Bundle through entry … resource.
    class Query
      LANGUAGE = "application/x-fhir-query"
      RESULT_PARAMS = %w[_sort _include _revinclude _count _elements _summary _total _contained _containedType].freeze
      # A {{…}} template stays whole even when it contains &.
      PARAM = /(?:\{\{.*?\}\}|[^&])+/

      attr_reader :form, :name, :type, :names, :codes

      def self.from(form, extension)
        expression = extension["valueExpression"]
        return unless extension["url"].to_s.end_with?("/variable") &&
                      QuestionnaireUsage.text(expression, "language") == LANGUAGE

        name, text = %w[name expression].map { |key| QuestionnaireUsage.text(expression, key) }
        new(form, name, text) if name && text
      end

      # Undecodable %-sequences are kept as written.
      def self.decode(text)
        URI.decode_uri_component(text)
      rescue ArgumentError
        text
      end

      # [name without modifiers, value] of each parameter, the value decoded unless it holds a template.
      def self.params(query)
        query.to_s.scan(PARAM).map do |param|
          name, value = param.split("=", 2)
          value = value.to_s
          [decode(name).split(":").first.to_s, value.include?("{{") ? value : decode(value)]
        end
      end

      def self.type?(segment) = FHIR::RESOURCES.include?(segment)

      def initialize(form, name, text)
        @form = form
        @name = name
        @text = text
        path, query = text.split("?", 2)
        segments = path.split("/").reject(&:empty?)
        index = segments.rindex { |segment| Query.type?(segment) }
        @type = index ? segments[index] : segments.last
        @read = index && read_path?(segments, index)
        parse_params(Query.params(query), index && compartment(segments, index))
      end

      def read? = @read

      def uses
        @uses ||= form.uses(name) { |chain| read? ? chain.paths_for(type) : chain.bundle_paths_for(type) }
      end

      def shown? = uses.any?

      def placement(group)
        Placement.new(self, group, test(group))
      end

      def heading = "**Query #{name}**: #{read? ? "reads one #{type} by id" : "searches #{type} resources"}"

      def context = "#{form.title} query #{name}"

      # The Request line, and, for a search no test of the group makes, how it compares to the group's searches.
      def details(group)
        ["Request: #{@text}", *(comparison(group) if group && !read? && names.any?)]
      end

      private

      def test(group)
        return group.find_test("read") if read?

        group.find_test("search", search_names: names) if names.any?
      end

      def comparison(group)
        searches = [*group.searches].map { |search| search[:names] }
        query = names.join(" + ")
        if searches.any? { |other| other.tally == names.tally }
          return "This group searches by the same parameters, #{query}, but has no test for it"
        end

        tested = searches.map { |other| other.join(" + ") }.join(", ")
        ["A search by #{query}", *("this group tests #{tested}" unless searches.empty?)].join("; ")
      end

      # An id follows the type; _history, _search or any $operation make it something else.
      def read_path?(segments, index)
        id = segments[index + 1]
        id && !id.start_with?("_", "$") && segments.none? { |segment| segment.start_with?("$") }
      end

      # patient for Patient/{{%patient.id}}/Observation.
      def compartment(segments, index)
        owner = segments[index - 2] if index >= 2
        owner.downcase if owner && Query.type?(owner)
      end

      def parse_params(params, compartment)
        @names = ([*compartment, *params.map(&:first)] - ["", *RESULT_PARAMS]).uniq
        @codes = read? ? nil : Codes.from_query(params)
      end
    end
  end
end
