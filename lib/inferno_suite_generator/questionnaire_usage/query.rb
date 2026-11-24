# frozen_string_literal: true

require "uri"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # One application/x-fhir-query variable on the root or an item. Parsed once: its text, resource type,
    # search parameter names (compartment first, then in query order) and [name, value] params.
    class Query
      LANGUAGE = "application/x-fhir-query"
      RESULT_PARAMS = %w[_sort _include _revinclude _count _elements _summary _total _contained _containedType].freeze
      # A {{…}} template stays whole even when it contains &.
      PARAM = /(?:\{\{.*?\}\}|[^&])+/

      SAME = "This group searches by the same parameters, %s, but has no test for it"

      # A parsed query: its text, resource type, compartment parameter and [name, value] params.
      Request = Struct.new(:text, :type, :compartment, :params) do
        # Search parameter names, compartment first, then in query order.
        def names = ([*compartment, *params.map(&:first)] - ["", *RESULT_PARAMS]).uniq
      end

      # The queries on the node and every item under it, in document order.
      def self.all(form, node)
        [*on(form, node), *QuestionnaireUsage.list(node, "item").flat_map { |item| all(form, item) }]
      end

      def self.on(form, node)
        QuestionnaireUsage.list(node, "extension").filter_map { |extension| from(form, extension) }
      end

      def self.from(form, extension)
        expression = extension["valueExpression"]
        return unless extension["url"].to_s.end_with?("/variable") &&
                      QuestionnaireUsage.text(expression, "language") == LANGUAGE

        name, text = %w[name expression].map { |key| QuestionnaireUsage.text(expression, key) }
        build(form, name, text) if name && text
      end

      def self.build(form, name, text)
        path, query = text.split("?", 2)
        type, read, compartment = target(path)
        (read ? ReadQuery : SearchQuery).new(form, name, Request.new(text, type, compartment, params(query)))
      end

      # [type, whether an id follows it, compartment parameter]; the type is the last segment naming a
      # resource type, else the last segment.
      def self.target(path)
        segments = path.split("/").reject(&:empty?)
        index = segments.rindex { |segment| FHIR::RESOURCES.include?(segment) }
        index ? [segments[index], read?(segments, index), compartment(segments, index)] : [segments.last]
      end

      # _history, _search or any $operation make it something other than a read.
      def self.read?(segments, index)
        id = segments[index + 1]
        id && !id.start_with?("_", "$") && segments.none? { |segment| segment.start_with?("$") }
      end

      # patient for Patient/{{%patient.id}}/Observation.
      def self.compartment(segments, index)
        owner = segments[index - 2] if index >= 2
        owner.downcase if FHIR::RESOURCES.include?(owner)
      end

      # [name without modifiers, value] of each parameter, the value decoded unless it holds a template.
      def self.params(query)
        query.to_s.scan(PARAM).map do |param|
          name, value = param.split("=", 2)
          value = value.to_s
          [decode(name).split(":").first.to_s, value.include?("{{") ? value : decode(value)]
        end
      end

      # Undecodable %-sequences are kept as written.
      def self.decode(text)
        URI.decode_uri_component(text)
      rescue ArgumentError
        text
      end

      # The comparison line of a search no test of the group makes, against the group's searches.
      def self.comparison(names, searches)
        query = names.join(" + ")
        return format(SAME, query) if searches.any? { |other| other.tally == names.tally }

        ["A search by #{query}", *("this group tests #{joined(searches)}" unless searches.empty?)].join("; ")
      end

      def self.joined(searches) = searches.map { |other| other.join(" + ") }.join(", ")

      attr_reader :form, :name

      def initialize(form, name, request)
        @form = form
        @name = name
        @request = request
      end

      def type = @request.type

      def names = @request.names

      def uses
        @uses ||= form.uses(name) { |chain| paths(chain) }
      end

      def shown? = uses.any?

      def context = "#{form.title} query #{name}"

      def details(_group) = ["Request: #{@request.text}"]
    end

    # A query that reads one resource by id: its items read the resource directly. Matched by type only.
    class ReadQuery < Query
      def heading = "**Query #{name}**: reads one #{type} by id"

      def codes = nil

      def placement(group)
        Placement.new(self, group, group.find_test("read"))
      end

      private

      def paths(chain) = chain.paths_for(type)
    end

    # A search: its items read the Bundle through entry … resource. Matched by code and category too.
    class SearchQuery < Query
      def heading = "**Query #{name}**: searches #{type} resources"

      def codes
        @codes ||= Codes.from_query(@request.params)
      end

      # group: the group whose tests do not make this search, or nil.
      def details(group)
        comparison = Query.comparison(names, [*group.searches].map { |search| search[:names] }) if group && names.any?
        [*super, *comparison]
      end

      # A search without parameters has no test.
      def placement(group)
        Placement.new(self, group, (group.find_test("search", search_names: names) if names.any?))
      end

      private

      def paths(chain) = chain.bundle_paths_for(type)
    end
  end
end
