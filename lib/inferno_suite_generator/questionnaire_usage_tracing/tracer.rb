# frozen_string_literal: true

require_relative "ast"
require_relative "profile_matcher"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # Finds the questionnaire sources that link to each profile in the suite and
    # the items that use them.
    #
    # `trace` returns `{ profile_url => [trace entries] }`. Every `Questionnaire`
    # in `ig_resources` is traced.
    class Tracer
      def initialize(ig_resources, groups)
        @ig_resources = ig_resources
        @matcher = ProfileMatcher.new(groups, ig_resources)
      end

      def trace
        traces = {}
        @ig_resources.get_resources_by_type("Questionnaire").each do |questionnaire|
          form = Form.new(questionnaire.to_hash)
          form.query_variables.each { |variable| add_query(traces, form, variable) }
        end
        traces
      end

      private

      def add_query(traces, form, variable)
        input = ProfileMatcher.from_query(variable[:expression])
        context = "#{form.label} query #{variable[:name]}"
        result = @matcher.match(input[:resource_type], codes: input[:codes], context:)
        return unless result

        entry = query_entry(form, variable, input[:resource_type], result[:matched_by])
        result[:groups].each { |group| (traces[group.profile_url] ||= []) << entry }
      end

      def query_entry(form, variable, resource_type, matched_by)
        used_in, elements_read = usages(form, variable, resource_type)
        {
          source: "query", **form.header, name: variable[:name], defined_at: variable[:defined_at],
          query: variable[:expression], matched_by:, elements_read:, used_in:
        }
      end

      # The items in the variable's scope whose expressions read the query's own
      # type, and the element paths they read. Chains that pick another type
      # with `entry.resource.ofType(T)` read an `_include` target instead.
      def usages(form, variable, resource_type)
        found = form.scope(variable).flat_map do |item|
          form.expressions(item).filter_map do |expression|
            chains = own_type_chains(expression[:expression], variable[:name], resource_type)
            [Form.usage(item, expression[:extension]), chains] unless chains.empty?
          end
        end
        [found.map(&:first).uniq, paths_read(found.flat_map(&:last))]
      end

      def own_type_chains(expression, name, resource_type)
        Ast.paths(expression, name, bundle: true).select { |chain| [nil, resource_type].include?(chain[:type]) }
      end

      def paths_read(chains)
        chains.map { |chain| chain[:path] }.reject(&:empty?).uniq
      end

      # A questionnaire as a Hash, with the walks the tracer needs. The root and
      # the items that can define variables are its "owners".
      class Form
        VARIABLE_URL = "http://hl7.org/fhir/StructureDefinition/variable"
        FHIRPATH = "text/fhirpath"
        QUERY = "application/x-fhir-query"

        def self.usage(item, extension)
          { link_id: item["linkId"], text: item["text"], extension: }.compact
        end

        def initialize(questionnaire)
          @questionnaire = questionnaire
        end

        def header
          {
            questionnaire_url: @questionnaire["url"],
            questionnaire_version: @questionnaire["version"],
            questionnaire_title: @questionnaire["title"]
          }.compact
        end

        def label
          @questionnaire["title"] || @questionnaire["url"] || @questionnaire["id"]
        end

        # The x-fhir-query `variable` extensions on the root and on items, in
        # document order.
        def query_variables
          [@questionnaire, *descendants(@questionnaire)].flat_map do |owner|
            variables(owner).select { |expression| expression["language"] == QUERY }.map do |expression|
              { name: expression["name"], expression: expression["expression"], owner:, defined_at: defined_at(owner) }
            end
          end
        end

        # A root variable covers every item. An item variable covers that item
        # and its children.
        def scope(variable)
          owner = variable[:owner]
          owner.equal?(@questionnaire) ? descendants(owner) : [owner, *descendants(owner)]
        end

        # `{ extension:, expression: }` for each `text/fhirpath` expression in
        # the item's own extensions and their sub-extensions. Nested items are
        # not read. `extension` is the short name, like `initialExpression`.
        def expressions(item)
          list(item["extension"]).flat_map { |extension| extension_expressions(extension, short_name(extension)) }
        end

        private

        def extension_expressions(extension, name)
          value = extension["valueExpression"]
          own = value && value["language"] == FHIRPATH && value["expression"] ? [value["expression"]] : []
          own.map { |expression| { extension: name, expression: } } +
            list(extension["extension"]).flat_map { |sub_extension| extension_expressions(sub_extension, name) }
        end

        def short_name(extension)
          extension["url"].to_s.split("/").last.to_s.delete_prefix("sdc-questionnaire-")
        end

        def variables(owner)
          list(owner["extension"]).select { |extension| extension["url"] == VARIABLE_URL }
                                  .filter_map { |extension| extension["valueExpression"] }
        end

        def defined_at(owner)
          owner.equal?(@questionnaire) ? "root" : owner["linkId"]
        end

        def descendants(node)
          list(node["item"]).flat_map { |item| [item, *descendants(item)] }
        end

        def list(value)
          value.is_a?(Array) ? value : []
        end
      end
    end
  end
end
