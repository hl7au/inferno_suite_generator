# frozen_string_literal: true

require "fhirpath"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Reads `%Name` references and what chains from a name read in FHIRPath expressions.
    # Callers go through `Cache`, which parses each expression once.
    module Ast
      Start = Data.define(:shape, :type, :prefix)

      # What `%name` stands for where an expression reads it. `shape` is `:bundle` for a search's Bundle,
      # `:entries` for Bundle entries a chain picked, else `:resource`. `type` is the resource type when known;
      # `prefix` the element path the name is at, `""` at the resource itself and `nil` once a chain stopped.
      class Start
        def self.bundle = new(shape: :bundle, type: nil, prefix: "")
        def self.resource = new(shape: :resource, type: nil, prefix: "")

        # A chain's own type counts only from the resource itself.
        def type_of(chain)
          type || (chain[:type] if prefix == "")
        end

        def paths_of(chain)
          return [] unless prefix

          [chain[:path], *chain[:criteria]].map { |path| at(path) }.reject(&:empty?)
        end

        # Where a variable the chain defines starts.
        def after(chain)
          Start.new(shape: chain[:entries] ? :entries : :resource, type: type_of(chain),
                    prefix: (at(chain[:path]) if prefix && !chain[:stopped]))
        end

        private

        def at(path)
          [prefix, path].reject(&:empty?).join(".")
        end
      end

      ChainRead = Data.define(:type, :types, :paths, :alias_start)

      # One chain from a name, read from a Start. `types` holds every type a `where` branch names, and
      # `alias_start` is where a variable the chain defines starts.
      class ChainRead
        def self.of(chain, start)
          new(type: start.type_of(chain), types: chain[:types], paths: start.paths_of(chain),
              alias_start: start.after(chain))
        end

        # Whether it reads the resource itself, so a variable it defines stands for the resource.
        def resource?
          alias_start.prefix == ""
        end
      end

      module_function

      def references_in(tree)
        nodes(tree).filter_map { |node| constant_name(node) }.uniq
      end

      def chains_in(tree, name, shape:)
        chains(tree, name).map { |steps| ChainPath.read(steps, shape:) }
      end

      # The tree, or `{}` for an empty expression or one that doesn't parse.
      def parse(expression)
        return {} if expression.to_s.strip.empty?

        Fhirpath::Parser.parse(expression)
      rescue Fhirpath::Error => e
        QuestionnaireUsage.log("skipping FHIRPath #{expression.inspect}: #{e.message}")
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
        steps_from(node) { |term| [] if constant_name(term.dig("children", 0, "children", 0)) == name }
      end

      # The steps of the chain ending at `node`, or `nil`. The block maps the `TermExpression` the chain
      # starts at to its first steps, or to `nil` to skip the chain.
      def steps_from(node, &)
        case node["type"]
        when "InvocationExpression", "IndexerExpression"
          base, step = children(node)
          steps = steps_from(base, &)
          steps && [*steps, step(node["type"], step)]
        when "TermExpression" then yield node
        end
      end

      # The element paths a `where`, `exists`, `all` or `select` argument reads, relative to its element.
      # A chain starting elsewhere, like `%name` or `now()`, reads only its own start's arguments.
      def criteria_paths(node)
        return [] unless node.is_a?(Hash)

        steps = steps_from(node) { |term| relative_start(term) }
        return ChainPath.relative_paths(steps) if steps

        starts_elsewhere = %w[InvocationExpression IndexerExpression].include?(node["type"])
        (starts_elsewhere ? children(node).first(1) : children(node)).flat_map { |child| criteria_paths(child) }
      end

      # The steps a chain from `$this` (none) or from a member starts with.
      def relative_start(term)
        start = children(term).first
        invocation = children(start).first if start&.dig("type") == "InvocationTerm"
        case invocation&.dig("type")
        when "MemberInvocation" then [step("InvocationExpression", invocation)]
        when "ThisInvocation" then []
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

      # Parses each expression once, however many sources and aliases read it.
      class Cache
        def initialize
          @trees = {}
          @references = {}
          @chains = {}
        end

        # The `%Name` names the expression references, without duplicates.
        def references(expression)
          @references[expression] ||= Ast.references_in(tree(expression))
        end

        # A ChainRead per longest chain from `%name`, nested ones included, read from `from`, a Start.
        def reads(expression, name, from:)
          return [] unless references(expression).include?(name)

          chains(expression, name, from.shape).map { |chain| ChainRead.of(chain, from) }
        end

        private

        def chains(expression, name, shape)
          @chains[[expression, name, shape]] ||= Ast.chains_in(tree(expression), name, shape:).freeze
        end

        def tree(expression)
          @trees[expression] ||= Ast.parse(expression)
        end
      end

      # Turns a chain's steps into `{ type:, types:, path:, stopped:, criteria: }`, plus `entries: true` when it
      # ends at Bundle entries. `types` holds every type any `where` branch names; `stopped`, that it left the
      # resource or stopped at `ofType`/`select`. `shape:` is the shape of the chain's Start.
      module ChainPath
        STOP_FUNCTIONS = %w[ofType select resolve children descendants].freeze
        CRITERIA_FUNCTIONS = %w[where exists all select].freeze
        EXTENSION_MEMBERS = %w[extension modifierExtension].freeze
        # The functions that pick some of the Bundle entries, as an indexer does.
        ENTRY_PICKS = %w[where first last tail skip take single].freeze
        BUNDLE_READ = { type: nil, types: [], path: "", stopped: true, criteria: [] }.freeze
        # The node types a condition holds for all of, and those an extension's `url` condition is also read through.
        AND_NODES = %w[AndExpression TermExpression ParenthesizedTerm].freeze
        URL_NODES = [*AND_NODES, "ParamList", "InvocationTerm"].freeze

        module_function

        def read(steps, shape:)
          case shape
          when :entries then read_entries(steps)
          when :bundle then read_bundle(steps)
          else read_path(steps)
          end
        end

        # The paths a chain inside a criteria argument reads, except `resourceType`, which isn't an element.
        def relative_paths(steps)
          read = read_path(steps)
          [read[:path], *read[:criteria]].reject { |path| path.empty? || resource_type_path?(path) }
        end

        # A chain that never reaches `entry`, like `%q.total`, reads the Bundle itself: no element, and
        # stopped, so an alias of it gets no prefix.
        def read_bundle(steps)
          member?(steps.first, "entry") ? read_entries(steps.drop(1)) : BUNDLE_READ
        end

        # The steps after `entry`: picks before `resource`, where `where(resource is T)` or `ofType(T)` gives the type.
        # A chain that only picks entries ends at entries, and an alias of it reads `resource` the same way; one
        # doing anything else with them, like `count()` or `fullUrl`, reads the Bundle.
        def read_entries(steps)
          between = steps.take_while { |step| step[:kind] != :member }
          rest = steps.drop(between.size)
          return read_resource(rest.drop(1), entry_type(between)) if member?(rest.first, "resource")
          return BUNDLE_READ unless rest.empty? && between.all? { |step| entry_pick?(step) }

          type = entry_type(between)
          { type:, types: [type].compact, path: "", stopped: false, criteria: [], entries: true }
        end

        def entry_type(between)
          between.filter_map { |step| entry_filter_type(step) }.last
        end

        def entry_pick?(step)
          step[:kind] == :index || (step[:kind] == :function && ENTRY_PICKS.include?(step[:name]))
        end

        # The steps after `resource`, with the type an entry filter gave.
        def read_resource(steps, filter_type)
          of_type = type_name(steps.shift) if function?(steps.first, "ofType")
          read = read_path(steps)
          read.merge(type: of_type || filter_type || read[:type],
                     types: [of_type, filter_type, *read[:types]].compact.uniq)
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
          StepReader.new.read(steps)
        end

        def resource_type_path?(path)
          path.split(".").last == "resourceType"
        end

        # The `X` of a `url = 'X'` condition, also inside `and`, parentheses or an unqualified `exists(...)`. One
        # inside another chain, like `extension.where(url = 'Y')`, is about a sub-extension, so it is skipped.
        def url_filter(args)
          literals(args.first, "url", URL_NODES).first if args.one?
        end

        # The `X` of each `left = 'X'` in a condition, read through the node types in `through` and an unqualified
        # `exists(...)`, which only `InvocationTerm` reaches: a qualified call is in an `InvocationExpression`.
        def literals(node, left, through)
          case node&.dig("type")
          when "EqualityExpression" then [equal_literal(node, left)].compact
          when "FunctionInvocation"
            name, params = Ast.children(Ast.children(node).first)
            Ast.identifier(name) == "exists" ? literals(params, left, through) : []
          when *through then Ast.children(node).flat_map { |child| literals(child, left, through) }
          else []
          end
        end

        def equal_literal(node, left)
          name, value = Ast.children(node)
          string_literal(value) if node["terminalNodeText"].to_a == ["="] && name&.dig("text") == left
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

      # Reads the path, criteria and types of the steps after a chain's start.
      class StepReader
        def initialize
          @names = []
          @criteria = []
          @types = []
          @type = nil
        end

        def read(steps)
          stopped = false
          steps.each do |step|
            stopped = read_step(step)
            break if stopped
          end
          { type: @type, types: @types.uniq, path: @names.join("."), stopped:, criteria: @criteria.uniq }
        end

        private

        # Whether the chain stops at this step.
        def read_step(step)
          case step[:kind]
          when :member
            @names << step[:name]
            false
          when :function
            read_function(step) unless extension_filter(step)
            ChainPath::STOP_FUNCTIONS.include?(step[:name])
          else false
          end
        end

        def read_function(step)
          read_criteria(step) if ChainPath::CRITERIA_FUNCTIONS.include?(step[:name])
          read_resource_type(step[:args].first) if step[:name] == "where" && step[:args].one? && @names.empty?
        end

        def read_criteria(step)
          prefix = @names.join(".")
          paths = step[:args].flat_map { |arg| Ast.criteria_paths(arg) }
          @criteria.concat(paths.map { |path| [prefix, path].reject(&:empty?).join(".") })
        end

        # A `where(resourceType = 'T')` on the chain's start picks resources of type `T`: the one it requires,
        # alone or in an `and`, and every one it names in any `and` or `or` branch.
        def read_resource_type(condition)
          @type ||= ChainPath.literals(condition, "resourceType", ChainPath::AND_NODES).first
          @types.concat(ChainPath.literals(condition, "resourceType", [*ChainPath::AND_NODES, "OrExpression"]))
        end

        # Folds an extension filter's url into the path, and returns whether it did.
        def extension_filter(step)
          if step[:name] == "extension" && (url = ChainPath.string_literal(step[:args].first))
            @names << "extension[url=#{url}]"
          elsif step[:name] == "where" && ChainPath::EXTENSION_MEMBERS.include?(@names.last) &&
                (url = ChainPath.url_filter(step[:args]))
            @names[-1] = "#{@names.last}[url=#{url}]"
          end
        end
      end
    end
  end
end
