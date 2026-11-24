# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # One FHIRPath invocation chain read from the fhirpath-rb parse tree: one that starts at an external
    # constant, such as %patient.name.family, or, with no name, one relative to a filtered element.
    class Chain
      SPINE = %w[InvocationExpression IndexerExpression].freeze
      LITERAL = /\A'(.*)'\z/
      FILTERS = %w[where exists all select].freeze
      STOPS = %w[ofType select resolve children descendants].freeze
      EXTENSIONS = %w[extension modifierExtension].freeze

      # kind is :member, :function, :index or :other; params are the parse nodes of its arguments.
      Step = Struct.new(:kind, :name, :params) do
        def literal = (params.first["text"].to_s[LITERAL, 1] if params.size == 1)

        # { field => 'v' } for where(field = 'v'), else {}.
        def where
          condition = params.first if name == "where" && params.size == 1
          return {} unless condition&.dig("terminalNodeText") == ["="]

          left, right = condition.fetch("children", []).map { |side| side["text"].to_s }
          { left => right[LITERAL, 1] }.compact
        end

        def function?(names) = kind == :function && names.include?(name)

        # The element a member step or extension('<url>') reads; resourceType is not an element.
        def elements
          return [literal&.then { |url| "#{name}[url=#{url}]" } || name] if function?(EXTENSIONS)

          kind == :member && name != "resourceType" ? [name] : []
        end
      end

      # Follows the steps of one chain and collects the element paths they read.
      class Reading
        def initialize
          @path = []
          @filtered = []
        end

        # The path the steps reach, then the paths their filter arguments read.
        def paths(steps)
          steps.each do |step|
            read(step)
            break if step.function?(STOPS)
          end
          [@path.join("."), *@filtered].reject(&:empty?).uniq
        end

        private

        def read(step)
          last = @path.last
          url = step.where["url"]
          if url && EXTENSIONS.include?(last)
            @path[-1] = "#{last}[url=#{url}]"
          elsif step.function?(FILTERS)
            filter(step.params)
          else
            @path.concat(step.elements)
          end
        end

        # Arguments of where, exists, all and select read paths relative to the filtered element.
        def filter(params)
          prefix = @path.join(".")
          params.flat_map { |param| Chain.relative(param) }.flat_map(&:paths).each do |path|
            @filtered << [prefix, path].reject(&:empty?).join(".")
          end
        end
      end

      attr_reader :name, :steps

      # Every chain on an external constant in the expression, in document order. When the whole
      # expression is one such chain, it comes first and is whole?.
      def self.parse(text)
        text.strip.empty? ? [] : chains(Fhirpath::Parser.parse(text).dig("children", 0))
      rescue Fhirpath::Error => e
        QuestionnaireUsage.log(%(skipping FHIRPath "#{text}": #{e.message}))
        []
      end

      def self.chains(expression)
        chains = collect(expression)
        from(expression)&.name ? [chains.first.as_whole, *chains.drop(1)] : chains
      end

      def self.collect(node)
        chain = from(node)
        children = chain ? chain.arguments : node.fetch("children", [])
        [*(chain if chain&.name), *children.flat_map { |child| collect(child) }]
      end

      # The relative chains in a filter argument; chains on external constants are collected separately.
      def self.relative(node)
        chain = from(node)
        return chain.name ? [] : [chain] if chain

        node.fetch("children", []).flat_map { |child| relative(child) }
      end

      # Unwinds the left spine of a.b[0].c() down to its start.
      def self.from(node, steps = [])
        return start(node, steps) unless SPINE.include?(node["type"])

        from(node.dig("children", 0), [step(node), *steps])
      end

      # A chain on %name, or a relative one on $this or a bare identifier; nil for anything else.
      def self.start(node, steps)
        term = node.dig("children", 0) if node["type"] == "TermExpression"
        child = term&.dig("children", 0)
        case term&.dig("type")
        when "ExternalConstantTerm" then new(identifier(child.dig("children", 0)), steps)
        when "InvocationTerm" then new(nil, [invocation_step(child), *steps])
        end
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

      def self.identifier(node)
        node&.dig("text")&.delete("`")
      end

      def initialize(name, steps)
        @name = name
        @steps = steps
      end

      # Whether the chain is a whole expression, so a variable bound to it carries its position.
      def whole? = false

      def as_whole = Whole.new(name, steps)

      # The chain that reads this one through a variable, started here instead.
      def append(chain) = chain.dup.rebase(name, steps + chain.steps)

      def arguments
        steps.flat_map(&:params)
      end

      # T for a leading where(resourceType = 'T').
      def picked_type
        steps.first&.where.to_h["resourceType"]
      end

      # The dot-joined element paths read on the resource, after a leading type pick.
      def paths
        Reading.new.paths(steps.drop(picked_type ? 1 : 0))
      end

      # The paths the chain reads on a resource of the given type, or nil when it picks another type.
      def paths_for(type)
        paths if [nil, type].include?(picked_type)
      end

      # The paths a chain on a search's Bundle reads on its resources of the given type (see Entries).
      def bundle_paths_for(type) = Entries.new(steps).paths_for(type)

      # Like bundle_paths_for, but only when the chain picks the type.
      def picked_bundle_paths_for(type) = Entries.new(steps).picked_paths_for(type)

      protected

      def rebase(name, steps)
        @name = name
        @steps = steps
        self
      end
    end

    # A chain that is a whole expression.
    class Whole < Chain
      def whole? = true
    end
  end
end
