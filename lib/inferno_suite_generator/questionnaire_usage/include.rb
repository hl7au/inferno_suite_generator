# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # One target type of a query's _include=<QueryType>:<param>[:<Target>]: the resources it fetches. Its uses
    # are the chains on the query's results that pick the target type. Matched by type only.
    class Include
      PARAM = "_include"

      # The include sources of the query's [name, value] params, one per target type; logs the untraced ones.
      def self.all(query, params)
        params.select { |name, _value| name.split(":").first == PARAM }.flat_map { |param| of(query, *param) }
      end

      # _include:iterate and an _include of another type are not traced.
      def self.of(query, name, value)
        return skip(query, name, value) unless name == PARAM && value.split(":").first == query.type

        targets(query, value).map { |type| new(query, value, type) }
      end

      def self.skip(query, name, value)
        QuestionnaireUsage.log("skipping #{name}=#{value} in #{query.context}: " \
                               "only _include of #{query.type} is traced")
        []
      end

      # The explicit target, else the SearchParameter's targets, else the types the form picks on the results.
      def self.targets(query, value)
        _type, param, target = value.split(":", 3)
        types = [*target.presence].presence || search_targets(query, param).presence ||
                (query.picked_types - [query.type])
        QuestionnaireUsage.log("unresolved #{query.context} include #{value}: no target type") if types.empty?
        types.uniq
      end

      def self.search_targets(query, param)
        [*query.form.ig_resources.search_param_by_exact_resource_and_code(query.type, param)&.target]
      end

      # [test, group] for the first include test of a group of the query's type: in each group, one with the
      # query's parameters, then any; nil when there is none.
      def self.include_test(query, targets, groups)
        names = query.names
        groups.select { |other| other.resource == query.type }.lazy.filter_map do |other|
          found = other.find_test("include", search_names: names, include_targets: targets) ||
                  other.find_test("include", include_targets: targets)
          [found, other] if found
        end.first
      end

      attr_reader :query, :value, :type

      def initialize(query, value, type)
        @query = query
        @value = value
        @type = type
      end

      def form = query.form

      def codes = nil

      # An include of the query's own type has no uses: its resources look like the query's own results.
      def uses
        @uses ||= type == query.type ? [] : query.picked_uses(type)
      end

      # It belongs to a query that is shown because it has an _include.
      def shown? = true

      def context = "#{query.context} include #{value}"

      def heading = "**Query #{query.name}**: fetches #{type} resources through _include=#{value}"

      def details(_group) = ["Request: #{query.text}"]

      def unused_lines = []

      def placement(group, groups)
        Placement.new(self, group, *Include.include_test(query, [group.resource], groups))
      end
    end
  end
end
