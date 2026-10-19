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
        source = { name: variable[:name], owner: variable[:owner], bundle: true }
        used_in, elements_read = Usages.new(form, source, ->(type) { [nil, resource_type].include?(type) }).call
        {
          source: "query", **form.header, name: variable[:name], defined_at: variable[:defined_at],
          query: variable[:expression], matched_by:, elements_read:, used_in:
        }
      end

      # The usages of one source in one form: the items in its scope that read
      # it, directly or through aliases, and the element paths they read.
      #
      # An alias is a `text/fhirpath` variable whose expression reads the source
      # or another alias. Its prefix is the parent's prefix plus the path of its
      # own chain, or `nil` when that chain stopped at `ofType` or `select`. It
      # keeps the chain's type, and only chains whose type `accept` takes count.
      class Usages
        Name = Struct.new(:name, :owner, :bundle, :type, :prefix, :alias, keyword_init: true)

        # `source` is `{ name:, owner:, bundle: }`. `bundle: true` for a query,
        # whose `%Name` is a Bundle.
        def initialize(form, source, accept)
          @form = form
          @accept = accept
          @source = Name.new(**source, type: nil, prefix: "", alias: false)
          @names = [@source]
          @paths = []
        end

        # `[used_in, elements_read]`
        def call
          resolve_aliases
          used_in = @form.scope(@source.owner).flat_map { |item| item_usages(item) }
          [used_in.uniq, @paths.reject(&:empty?).uniq]
        end

        private

        # Repeats until no new alias is found. Each variable becomes an alias at
        # most once, so a form whose variables reference each other can't loop.
        def resolve_aliases
          pending = @form.fhirpath_variables.select { |variable| @form.covers?(@source.owner, variable[:owner]) }
          loop do
            break unless pending.reject! { |variable| add_alias(variable) }
          end
        end

        def add_alias(variable)
          reads = reads_of(variable[:expression], variable[:owner])
          return false if reads.empty?

          name, chain = reads.first
          @paths.concat(reads.filter_map { |read| read_path(*read) })
          @names << Name.new(name: variable[:name], owner: variable[:owner], bundle: false, alias: true,
                             type: type_of(name, chain), prefix: chain[:stopped] ? nil : read_path(name, chain))
          true
        end

        # One usage per expression that reads the source. `via` names the alias
        # it went through, and is left out when the expression reads the source
        # directly.
        def item_usages(item)
          @form.expressions(item).filter_map do |expression|
            reads = reads_of(expression[:expression], item)
            next if reads.empty?

            @paths.concat(reads.filter_map { |read| read_path(*read) })
            Form.usage(item, expression[:extension], via: via(reads.map(&:first)))
          end
        end

        def via(names)
          names.first.name if names.all?(&:alias)
        end

        # `[name, chain]` for each accepted chain in the expression from a name
        # visible at `node`.
        def reads_of(expression, node)
          @names.select { |name| expression.include?(name.name) && @form.covers?(name.owner, node) }
                .flat_map do |name|
            Ast.paths(expression, name.name, bundle: name.bundle)
               .filter_map { |chain| [name, chain] if @accept.call(type_of(name, chain)) }
          end
        end

        def type_of(name, chain)
          name.type || chain[:type]
        end

        def read_path(name, chain)
          [name.prefix, chain[:path]].reject(&:empty?).join(".") if name.prefix
        end
      end

      # A questionnaire as a Hash, with the walks the tracer needs. The root and
      # the items that can define variables are its "owners".
      class Form
        VARIABLE_URL = "http://hl7.org/fhir/StructureDefinition/variable"
        FHIRPATH = "text/fhirpath"
        QUERY = "application/x-fhir-query"

        def self.usage(item, extension, via: nil)
          { link_id: item["linkId"], text: item["text"], extension:, via: }.compact
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
          variables_in(QUERY)
        end

        # The `text/fhirpath` `variable` extensions, in document order.
        def fhirpath_variables
          @fhirpath_variables ||= variables_in(FHIRPATH)
        end

        # A root variable covers every item. An item variable covers that item
        # and its children.
        def scope(owner)
          owner.equal?(@questionnaire) ? descendants(owner) : [owner, *descendants(owner)]
        end

        # Whether a variable defined on `owner` (the root or an item) is visible
        # at `node`.
        def covers?(owner, node)
          return true if owner.equal?(@questionnaire)

          node = parents[node] until node.nil? || node.equal?(owner)
          !node.nil?
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

        def variables_in(language)
          [@questionnaire, *descendants(@questionnaire)].flat_map do |owner|
            variables(owner).select { |expression| expression["language"] == language }.map do |expression|
              { name: expression["name"], expression: expression["expression"].to_s, owner:,
                defined_at: defined_at(owner) }
            end
          end
        end

        def variables(owner)
          list(owner["extension"]).select { |extension| extension["url"] == VARIABLE_URL }
                                  .filter_map { |extension| extension["valueExpression"] }
        end

        def parents
          @parents ||= [@questionnaire, *descendants(@questionnaire)]
                       .each_with_object({}.compare_by_identity) do |node, map|
            list(node["item"]).each { |child| map[child] = node }
          end
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
