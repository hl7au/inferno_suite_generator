# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # One FHIRPath invocation chain that starts at an external constant, such as %patient.name.family,
    # read from the fhirpath-rb parse tree.
    class Chain
      SPINE = %w[InvocationExpression IndexerExpression].freeze
      TYPE_PICK = /\A'(\w+)'\z/

      # kind is :member, :function, :index or :other; params are the parse nodes of its arguments.
      Step = Struct.new(:kind, :name, :params) do
        # T for where(resourceType = 'T'), else nil.
        def picked_type
          return unless name == "where" && params.size == 1

          condition = params.first
          left, right = condition.fetch("children", []).map { |side| side["text"].to_s }
          right[TYPE_PICK, 1] if condition["terminalNodeText"] == ["="] && left == "resourceType"
        end
      end

      attr_reader :name, :steps

      # Every chain on an external constant in the expression, in document order.
      def self.parse(text)
        return [] if text.strip.empty?

        collect(Fhirpath::Parser.parse(text))
      rescue Fhirpath::Error => e
        QuestionnaireUsage.log(%(skipping FHIRPath "#{text}": #{e.message}))
        []
      end

      def self.collect(node)
        chain = from(node)
        children = chain ? chain.arguments : node.fetch("children", [])
        [*chain, *children.flat_map { |child| collect(child) }]
      end

      # Unwinds the left spine of a.b[0].c() down to its start.
      def self.from(node, steps = [])
        return constant_name(node)&.then { |name| new(name, steps) } unless SPINE.include?(node["type"])

        from(node.dig("children", 0), [step(node), *steps])
      end

      def self.step(spine)
        right = spine.dig("children", 1)
        spine["type"] == "IndexerExpression" ? Step.new(:index, nil, [right]) : invocation_step(right)
      end

      def self.invocation_step(invocation)
        child = invocation.dig("children", 0)
        case invocation["type"]
        when "MemberInvocation" then Step.new(:member, identifier(child), [])
        when "FunctionInvocation"
          Step.new(:function, identifier(child.dig("children", 0)), child.dig("children", 1, "children") || [])
        else Step.new(:other, nil, [])
        end
      end

      def self.constant_name(node)
        term = node.dig("children", 0)
        return unless node["type"] == "TermExpression" && term&.dig("type") == "ExternalConstantTerm"

        identifier(term.dig("children", 0, "children", 0))
      end

      def self.identifier(node)
        node&.dig("text")&.delete("`")
      end

      def initialize(name, steps)
        @name = name
        @steps = steps
      end

      def arguments
        steps.flat_map(&:params)
      end

      def picked_type
        steps.first&.picked_type
      end

      # The dot-joined element path read on the resource, after a leading type pick.
      def path
        steps.drop(picked_type ? 1 : 0).select { |step| step.kind == :member }.map(&:name).join(".")
      end

      # The paths the chain reads on a resource of the given type, or nil when it picks another type.
      def paths_for(type)
        [path].reject(&:empty?) if [nil, type].include?(picked_type)
      end
    end
  end
end
