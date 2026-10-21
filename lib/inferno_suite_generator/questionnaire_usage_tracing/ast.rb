# frozen_string_literal: true

require "fhirpath"
require_relative "log"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # Reads `%Name` references and element paths from FHIRPath expressions.
    #
    # Each reader takes an expression, and has an `_in` variant that takes the
    # tree `parse` returns, so a caller that keeps trees parses each expression
    # once.
    module Ast
      module_function

      # The `%Name` names the expression references, without duplicates.
      def references(expression)
        references_in(parse(expression))
      end

      def references_in(tree)
        nodes(tree).filter_map { |node| constant_name(node) }.uniq
      end

      # One `{ type:, path:, stopped: }` per longest chain that starts with
      # `%name`, including chains nested in function arguments.
      def paths(expression, name, bundle:)
        paths_in(parse(expression), name, bundle:)
      end

      def paths_in(tree, name, bundle:)
        chains(tree, name).map { |steps| ChainPath.read(steps, bundle:) }
      end

      # The tree, or `{}` for an empty expression or one that doesn't parse.
      def parse(expression)
        return {} if expression.to_s.strip.empty?

        Fhirpath::Parser.parse(expression)
      rescue Fhirpath::Error => e
        QuestionnaireUsageTracing.log("skipping FHIRPath #{expression.inspect}: #{e.message}")
        {}
      end

      def nodes(node, found = [])
        return found unless node.is_a?(Hash)

        found << node
        children(node).each { |child| nodes(child, found) }
        found
      end

      # Step lists of the longest chains from `%name`.
      def chains(node, name, found = [])
        return found unless node.is_a?(Hash)

        steps = chain_steps(node, name)
        nested = steps ? steps.flat_map { |step| step[:args] } : children(node)
        found << steps if steps
        nested.each { |child| chains(child, name, found) }
        found
      end

      def chain_steps(node, name)
        case node["type"]
        when "InvocationExpression", "IndexerExpression"
          base, step = children(node)
          steps = chain_steps(base, name)
          steps && [*steps, step(node["type"], step)]
        when "TermExpression"
          [] if constant_name(node.dig("children", 0, "children", 0)) == name
        end
      end

      def step(expression_type, node)
        return { kind: :index, args: [node] } if expression_type == "IndexerExpression"

        case node["type"]
        when "MemberInvocation" then { kind: :member, name: identifier(children(node).first), args: [] }
        when "FunctionInvocation" then function_step(children(node).first)
        else { kind: :other, args: [] }
        end
      end

      def function_step(functn)
        name_node, param_list = children(functn)
        { kind: :function, name: identifier(name_node), args: param_list ? children(param_list) : [] }
      end

      # `%name`, `` %`vs-x` `` and `%'vs-x'` all give the bare name.
      def constant_name(node)
        return unless node.is_a?(Hash) && node["type"] == "ExternalConstant"

        name = node.dig("children", 0, "text") || node["terminalNodeText"].to_a.last
        name.to_s.delete_prefix("%").delete_prefix("`").delete_suffix("`").delete_prefix("'").delete_suffix("'")
      end

      def identifier(node)
        node&.dig("text").to_s.delete_prefix("`").delete_suffix("`")
      end

      def children(node)
        node["children"] || []
      end

      # `references` and `paths` that parse each expression once, however many
      # sources and aliases read it.
      class Cache
        def initialize
          @trees = {}
          @references = {}
        end

        def references(expression)
          @references[expression] ||= Ast.references_in(tree(expression))
        end

        def paths(expression, name, bundle:)
          Ast.paths_in(tree(expression), name, bundle:)
        end

        private

        def tree(expression)
          @trees[expression] ||= Ast.parse(expression)
        end
      end

      # Turns the steps of one chain into `{ type:, path:, stopped: }`
      module ChainPath
        STOP_FUNCTIONS = %w[ofType select].freeze
        EXTENSION_MEMBERS = %w[extension modifierExtension].freeze
        # A chain that reads the Bundle itself instead of a resource in it.
        BUNDLE_READ = { type: nil, path: "", stopped: true }.freeze

        module_function

        def read(steps, bundle:)
          return read_bundle(steps) if bundle

          path, stopped = read_path(steps)
          { type: nil, path:, stopped: }
        end

        # A Bundle chain reads a resource through `entry` and then `resource`.
        # Functions and indexers between the two pick entries, and a
        # `where(resource is T)` among them gives the type, as does an
        # `ofType(T)` right after `resource`.
        #
        # A chain that never reaches `resource`, like `%q.total` or
        # `%q.entry.count()`, reads the Bundle, so it reads no profile element.
        # It counts as stopped, so an alias of it gets no prefix.
        def read_bundle(steps)
          return BUNDLE_READ unless member?(steps.first, "entry")

          between = steps.drop(1).take_while { |step| step[:kind] != :member }
          rest = steps.drop(1 + between.size)
          return BUNDLE_READ unless member?(rest.first, "resource")

          read_resource(rest.drop(1), between.filter_map { |step| entry_filter_type(step) }.last)
        end

        # The steps after `resource`, with the type an entry filter gave.
        def read_resource(steps, filter_type)
          of_type = type_name(steps.shift) if function?(steps.first, "ofType")
          path, stopped = read_path(steps)
          { type: of_type || filter_type, path:, stopped: }
        end

        # The `T` of `where(resource is T)` or `where(resource.is(T))`.
        def entry_filter_type(step)
          return unless function?(step, "where") && step[:args].one?

          condition = step[:args].first
          case condition["type"]
          when "TypeExpression" then type_of_is_operator(condition)
          when "InvocationExpression" then type_of_is_call(condition)
          end
        end

        def type_of_is_operator(condition)
          term, specifier = Ast.children(condition)
          return unless condition["terminalNodeText"].to_a == ["is"] && term&.dig("text") == "resource"

          clean_type(specifier&.dig("text"))
        end

        def type_of_is_call(condition)
          term, invocation = Ast.children(condition)
          return unless term&.dig("text") == "resource" && invocation&.dig("type") == "FunctionInvocation"

          step = Ast.function_step(Ast.children(invocation).first)
          type_name(step) if step[:name] == "is"
        end

        def read_path(steps)
          names = []
          steps.each do |step|
            next names << step[:name] if step[:kind] == :member
            next unless step[:kind] == :function
            return [names.join("."), true] if STOP_FUNCTIONS.include?(step[:name])

            read_extension_filter(step, names)
          end
          [names.join("."), false]
        end

        def read_extension_filter(step, names)
          if step[:name] == "extension" && (url = string_literal(step[:args].first))
            names << "extension[url=#{url}]"
          elsif step[:name] == "where" && EXTENSION_MEMBERS.include?(names.last) && (url = url_filter(step[:args]))
            names[-1] = "#{names.last}[url=#{url}]"
          end
        end

        # The `X` of a `url = 'X'` condition in the single argument. The
        # condition can sit inside `and`, parentheses or an unqualified
        # `exists(...)`, as in `where(exists(url = 'X') and ...)`. A condition
        # inside another chain, like `extension.where(url = 'Y')`, is about a
        # sub-extension and is not taken.
        def url_filter(args)
          url_condition(args.first) if args.one?
        end

        def url_condition(node)
          case node&.dig("type")
          when "EqualityExpression" then url_equality(node)
          when "AndExpression", "ParamList", "ParenthesizedTerm"
            Ast.children(node).lazy.filter_map { |child| url_condition(child) }.first
          when "TermExpression", "InvocationTerm" then url_condition(Ast.children(node).first)
          when "FunctionInvocation" then url_exists(*Ast.children(Ast.children(node).first))
          end
        end

        def url_equality(node)
          left, right = Ast.children(node)
          string_literal(right) if left&.dig("text") == "url"
        end

        # Reached only for an unqualified call: a qualified one is the right
        # child of an `InvocationExpression`, which `url_condition` skips.
        def url_exists(name, params = nil)
          url_condition(params) if Ast.identifier(name) == "exists"
        end

        def string_literal(node)
          node&.dig("text").to_s[/\A'(.*)'\z/m, 1]
        end

        def type_name(step)
          clean_type(step[:args].first&.dig("text"))
        end

        def clean_type(text)
          text.to_s.delete("`").delete_prefix("FHIR.")
        end

        def function?(step, name)
          step && step[:kind] == :function && step[:name] == name
        end

        def member?(step, name)
          step && step[:kind] == :member && step[:name] == name
        end
      end
    end
  end
end
