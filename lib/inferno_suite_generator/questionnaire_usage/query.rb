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
      MODIFIER = /:[^.]*/

      SAME = "This group searches by the same parameters, %s, but has no test for it"

      # A parsed query: its text, resource type, compartment parameter and [name, value] params.
      Request = Struct.new(:text, :type, :compartment, :params) do
        # Search parameter names without modifiers (subject:Patient.name is subject.name), compartment first,
        # then in query order.
        def names
          written = params.map { |name, _value| name.sub(MODIFIER, "") }
          ([*compartment, *written] - ["", *RESULT_PARAMS]).uniq
        end
      end

      # The queries on the node and every item under it, in document order; key is the node's (:root or linkId).
      def self.all(form, node, key = :root)
        items = QuestionnaireUsage.list(node, "item")
        [*on(form, node, key), *items.flat_map { |item| all(form, item, item["linkId"]) }]
      end

      def self.on(form, node, key)
        QuestionnaireUsage.list(node, "extension").filter_map { |extension| from(form, extension, key) }
      end

      # The name chains read the query by: unique per node, so same-name queries on other items stay apart.
      def self.key(name, node_key) = "#{name}@#{node_key}"

      def self.from(form, extension, node_key)
        expression = extension["valueExpression"]
        return unless extension["url"].to_s.end_with?("/variable") &&
                      QuestionnaireUsage.text(expression, "language") == LANGUAGE

        name, text = %w[name expression].map { |key| QuestionnaireUsage.text(expression, key) }
        build(form, [name, key(name, node_key)], text) if name && text
      end

      # No source for a query whose path names nothing.
      def self.build(form, names, text)
        path, query = text.split("?", 2)
        type, read, compartment = target(path)
        (read ? ReadQuery : SearchQuery).new(form, names, Request.new(text, type, compartment, params(query))) if type
      end

      # [type, whether an id follows it, compartment parameter]; the type is the last segment naming a
      # resource type, else the last segment.
      def self.target(path)
        segments = path.split("/").reject(&:empty?)
        index = segments.rindex { |segment| FHIR::RESOURCES.include?(segment) }
        index ? [segments[index], read?(segments, index), compartment(segments, index)] : [segments.last]
      end

      # An id follows the type; a later _history or _search, or any $operation, makes it something else.
      def self.read?(segments, index)
        rest = segments.drop(index + 1)
        rest.any? && rest.none? { |segment| segment.start_with?("_") } &&
          segments.none? { |segment| segment.start_with?("$") }
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
          [decode(name), value.include?("{{") ? value : decode(value)]
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

      def initialize(form, (name, key), request)
        @form = form
        @name = name
        @key = key
        @request = request
      end

      def type = @request.type

      def names = @request.names

      def uses
        @uses ||= form.uses(@key) { |chain| paths(chain) }
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
