# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # The FHIRPath variables visible on one node of a form: those of the nodes above it, then its own,
    # each bound to the chains its expression reads.
    class Scope
      LANGUAGES = ["text/fhirpath", Query::LANGUAGE].freeze
      # [name, expression] of each FHIRPath variable on the node, in document order.
      def self.definitions(data)
        QuestionnaireUsage.list(data, "extension").filter_map { |extension| definition(extension) }
      end

      # An x-fhir-query variable comes as [name, nil]: it is bound to its query, not to FHIRPath chains.
      def self.definition(extension)
        expression = extension["valueExpression"]
        language = QuestionnaireUsage.text(expression, "language")
        return unless extension["url"].to_s.end_with?("/variable") && LANGUAGES.include?(language)

        pair = [QuestionnaireUsage.text(expression, "name"), QuestionnaireUsage.text(expression, "expression")]
        [pair.first, (pair.last if language == "text/fhirpath")] if pair.all?
      end

      def initialize(form, bindings = {})
        @form = form
        @bindings = bindings
      end

      # The scope of the node with these definitions under this one; a variable sees only those before it.
      def inner(key, definitions)
        return self if definitions.empty?

        definition, *later = definitions
        name, text = definition
        bind(name, text ? variable(definition, key, later) : [Whole.new(Query.key(name, key), [])]).inner(key, later)
      end

      # The chains of an expression, read through the variables they start at.
      def chains(text) = @form.chains(text).flat_map { |chain| resolve(chain) }

      private

      # A later name an outer node also defines is not untraced: until it is defined here, the outer one applies.
      def variable(definition, key, later)
        name, text = definition
        early = @form.chains(text).map(&:name).uniq & (later.map(&:first) - @bindings.keys)
        early.empty? ? chains(text) : untraced(name, key, early)
      end

      def bind(name, chains) = Scope.new(@form, @bindings.merge(name => chains))

      # A variable bound to one whole chain carries its position: %Name.family continues %patient.name.
      def resolve(chain)
        bound = @bindings[chain.name]
        return [chain] unless bound

        head, *rest = bound
        head&.whole? ? [head.append(chain), *rest] : bound
      end

      def untraced(name, key, early)
        QuestionnaireUsage.log("untraced #{@form.title} variable #{name} on #{key == :root ? "root" : key}: " \
                               "it uses #{early.join(", ")}, defined after it")
        []
      end
    end
  end
end
