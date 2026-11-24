# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # One target type of a query's _include=<QueryType>:<param>[:<Target>]: the resources it fetches. Its uses
    # are the chains on the query's results that pick the target type. Matched by type only.
    class Include
      PARAM = "_include"

      # The include sources of the query's [name, value] params, one per parameter and target type; logs the
      # untraced ones.
      def self.all(query, params)
        written(params).flat_map { |param| of(query, *param) }.uniq { |include| [include.param, include.type] }
      end

      # A read by id takes no _include: its includes are logged, not traced.
      def self.read(query, params)
        written(params).each { |name, value| skip(query, "#{name}=#{value}", "a read by id takes no _include") }
        []
      end

      # The query's _include params of any kind; the same include written twice is one.
      def self.written(params) = params.uniq.select { |name, _value| name.split(":").first == PARAM }

      # The values of the query's own _include params that name a parameter, resolved or not.
      def self.values(query, params)
        params.select { |param| own?(query, *param) && param.last.split(":")[1].present? }.map(&:last).uniq
      end

      # _include:iterate and an _include of another type are not the query's own.
      def self.own?(query, name, value) = [name, value.split(":").first] == [PARAM, query.type]

      def self.of(query, name, value)
        reason = "only _include of #{query.type} is traced"
        return skip(query, "#{name}=#{value}", reason) unless own?(query, name, value)

        targets(query, value).map { |type| new(query, value, type) }
      end

      def self.skip(query, text, reason)
        QuestionnaireUsage.log("skipping #{text} in #{query.context}: #{reason}")
        []
      end

      # The explicit target, else the SearchParameter's targets, else the types the form picks on the results.
      # None without a parameter part.
      def self.targets(query, value)
        _type, param, target = value.split(":", 3)
        return unresolved(query, value, "no search parameter") if param.blank?

        types = found_targets(query, param, target).uniq
        types.empty? ? unresolved(query, value, "no target type") : types
      end

      def self.unresolved(query, value, reason)
        QuestionnaireUsage.log("unresolved #{query.context} include #{value}: #{reason}")
        []
      end

      def self.found_targets(query, param, target)
        [*target.presence].presence || search_targets(query, param).presence || (query.picked_types - [query.type])
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

      def param = value.split(":")[1]

      def codes = nil

      # An include of the query's own type has no uses: its resources look like the query's own results.
      def uses
        @uses ||= type == query.type ? [] : query.picked_uses(type)
      end

      def shown? = uses.any?

      def context = "#{query.context} include #{value}"

      def heading = "**Query #{query.name}**: fetches #{type} resources through _include=#{value}"

      def details(_group) = ["Request: #{query.text}"]

      def placement(group, groups)
        Placement.new(self, group, *Include.include_test(query, [group.resource], groups))
      end
    end
  end
end
