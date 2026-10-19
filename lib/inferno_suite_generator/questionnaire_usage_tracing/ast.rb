# frozen_string_literal: true

require "fhirpath"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # Reads `%Name` references and element paths from FHIRPath expressions.
    module Ast
      module_function

      # The `%Name` names the expression references, without duplicates.
      def references(expression)
        nodes(parse(expression)).filter_map { |node| constant_name(node) }.uniq
      end

      # One `{ type:, path:, stopped: }` per longest chain that starts with
      # `%name`, including chains nested in function arguments.
      def paths(expression, name, bundle:)
        chains(parse(expression), name).map { |steps| ChainPath.read(steps, bundle:) }
      end

      def parse(expression)
        return {} if expression.to_s.strip.empty?

        Fhirpath::Parser.parse(expression)
      rescue Fhirpath::Error => e
        puts "Questionnaire usage tracing: skipping FHIRPath #{expression.inspect}: #{e.message}"
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

      # Turns the steps of one chain into `{ type:, path:, stopped: }`
      module ChainPath
        STOP_FUNCTIONS = %w[ofType select].freeze
        BUNDLE_STEPS = %w[entry resource].freeze
        EXTENSION_MEMBERS = %w[extension modifierExtension].freeze

        module_function

        def read(steps, bundle:)
          type = nil
          if bundle
            steps = drop_bundle_steps(steps)
            type = type_name(steps.shift) if function?(steps.first, "ofType")
          end
          path, stopped = read_path(steps)
          { type:, path:, stopped: }
        end

        def drop_bundle_steps(steps)
          BUNDLE_STEPS.each do |member|
            break unless steps.first&.dig(:name) == member && steps.first[:kind] == :member

            steps = steps.drop(1).drop_while { |step| step[:kind] == :index }
          end
          steps
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
          step[:args].first&.dig("text").to_s.delete("`").delete_prefix("FHIR.")
        end

        def function?(step, name)
          step && step[:kind] == :function && step[:name] == name
        end
      end
    end
  end
end
