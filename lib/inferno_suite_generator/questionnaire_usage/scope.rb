# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # The FHIRPath variables visible on one node of a form: those of the nodes above it, then its own,
    # each bound to the chains its expression reads.
    class Scope
      # [name, expression] of each FHIRPath variable on the node, in document order.
      def self.definitions(data)
        QuestionnaireUsage.list(data, "extension").filter_map { |extension| definition(extension) }
      end

      def self.definition(extension)
        expression = extension["valueExpression"]
        return unless extension["url"].to_s.end_with?("/variable") &&
                      QuestionnaireUsage.text(expression, "language") == "text/fhirpath"

        pair = [QuestionnaireUsage.text(expression, "name"), QuestionnaireUsage.text(expression, "expression")]
        pair if pair.all?
      end

      def initialize(form, bindings = {})
        @form = form
        @bindings = bindings
      end

      # The scope of the node with these definitions under this one; a variable sees only those before it.
      def inner(key, definitions)
        return self if definitions.empty?

        (name, text), *later = definitions
        # A later name an outer node also defines is not untraced: until it is defined here, the outer one applies.
        early = @form.chains(text).map(&:name).uniq & (later.map(&:first) - @bindings.keys)
        bind(name, early.empty? ? chains(text) : untraced(name, key, early)).inner(key, later)
      end

      # The chains of an expression, read through the variables they start at.
      def chains(text) = @form.chains(text).flat_map { |chain| resolve(chain) }

      private

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
