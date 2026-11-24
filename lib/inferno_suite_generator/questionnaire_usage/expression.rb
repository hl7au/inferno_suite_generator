# frozen_string_literal: true

require "fhirpath"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Where a FHIRPath value came from: `shape` is `:bundle`, `:entries` or `:resource`; `type` is the resource type
    # a filter picked; `path` is its element path, "" at the resource and nil once it is no longer an element.
    # `carried` is the other element paths read to get it, like a filter's: every chain from the value reads them.
    Origin = Data.define(:shape, :type, :path, :carried) do
      def self.bundle = new(shape: :bundle, type: nil, path: "")
      def self.resource = new(shape: :resource, type: nil, path: "")

      def initialize(carried: [], **) = super
    end

    # What one chain from a `%name` reads: the element `paths`, every resource type its filters name (`types`),
    # and the Origin of its value, which a variable the chain defines is bound to.
    Read = Data.define(:origin, :paths, :types)

    # Reads fhirpath-rb's syntax tree: nested Hashes with "type", "text", "children" and "terminalNodeText".
    module Syntax
      # The node types a condition holds for all of, and those an extension's `url` condition is also read through.
      AND_NODES = %w[AndExpression TermExpression ParenthesizedTerm].freeze
      URL_NODES = [*AND_NODES, "ParamList", "InvocationTerm"].freeze

      module_function

      def children(node)
        node["children"] || []
      end

      # `%name`, `` %`vs-x` `` and `%'vs-x'` all give the bare name; nil for a node that is no `%name`.
      def constant_name(node)
        return unless node.is_a?(Hash) && node["type"] == "ExternalConstant"

        name = node.dig("children", 0, "text") || node["terminalNodeText"].to_a.last
        name.to_s.delete_prefix("%").delete_prefix("`").delete_suffix("`").delete_prefix("'").delete_suffix("'")
      end

      def identifier(node)
        node&.dig("text").to_s.delete_prefix("`").delete_suffix("`")
      end

      def string_literal(node)
        node&.dig("text").to_s[/\A'(.*)'\z/m, 1]
      end

      # The steps of the chain ending at `node`, or nil. The block maps the `TermExpression` the chain starts at
      # to its first steps, or to nil to skip the chain.
      def steps_from(node, &)
        case node["type"]
        when "InvocationExpression", "IndexerExpression"
          base, last = children(node)
          steps = steps_from(base, &)
          steps && [*steps, step(node["type"], last)]
        when "TermExpression" then yield node
        end
      end

      # One step of a chain: `{ kind: :member, name: }`, `{ kind: :function, name:, args: }` or an indexer's
      # `{ kind: :index, args: }`.
      def step(expression_type, node)
        return { kind: :index, args: [node] } if expression_type == "IndexerExpression"

        case node["type"]
        when "MemberInvocation" then { kind: :member, name: identifier(children(node).first), args: [] }
        when "FunctionInvocation" then function_step(children(node).first)
        else { kind: :other, args: [] }
        end
      end

      def function_step(function)
        name, params = children(function)
        { kind: :function, name: identifier(name), args: params ? children(params) : [] }
      end

      # The `X` of each `left = 'X'` in a condition, read through the node types in `through` and an unqualified
      # `exists(...)`, which only `InvocationTerm` reaches: a qualified call is in an `InvocationExpression`.
      def literals(node, left, through)
        case node&.dig("type")
        when "EqualityExpression" then [equal_literal(node, left)].compact
        when "FunctionInvocation"
          name, params = children(children(node).first)
          identifier(name) == "exists" ? literals(params, left, through) : []
        when *through then children(node).flat_map { |child| literals(child, left, through) }
        else []
        end
      end

      def equal_literal(node, left)
        name, value = children(node)
        string_literal(value) if node["terminalNodeText"].to_a == ["="] && name&.dig("text") == left
      end
    end

    # One FHIRPath expression, parsed once.
    class Expression
      include Syntax

      def initialize(text)
        @tree = parse(text)
        @chains = {}
      end

      # The `%name` names the expression references, without duplicates.
      def references
        @references ||= nodes(@tree).filter_map { |node| constant_name(node) }.uniq
      end

      # A Read per chain from each name in `env`, `{ name => Origin }`: the names in `env` order, and the chains
      # of one name in the order written, a chain before the chains in its arguments.
      def reads(env)
        env.flat_map do |name, origin|
          references.include?(name) ? chains(name).map { |steps| Chain.new(origin, steps).read } : []
        end
      end

      private

      # The tree, or `{}` for an empty expression or one that doesn't parse.
      def parse(text)
        return {} if text.to_s.strip.empty?

        ::Fhirpath::Parser.parse(text)
      rescue ::Fhirpath::Error => e
        QuestionnaireUsage.log("skipping FHIRPath #{text.inspect}: #{e.message}")
        {}
      end

      def nodes(node, found = [])
        return found unless node.is_a?(Hash)

        found << node
        children(node).each { |child| nodes(child, found) }
        found
      end

      # The step lists of the longest chains from `%name`.
      def chains(name)
        @chains[name] ||= find_chains(@tree, name, [])
      end

      def find_chains(node, name, found)
        return found unless node.is_a?(Hash)

        steps = steps_from(node) { |term| [] if constant_name(term.dig("children", 0, "children", 0)) == name }
        found << steps if steps
        nested = steps ? steps.flat_map { |step| step[:args] } : children(node)
        nested.each { |child| find_chains(child, name, found) }
        found
      end
    end

    # The steps after a `%name`, like `.entry.resource.where(status = 'final').value`, read from the name's Origin.
    class Chain
      include Syntax

      # Functions after which the value is no longer an element of the resource.
      STOPS = %w[ofType select resolve children descendants].freeze
      # Functions whose argument reads elements of what they are called on.
      CRITERIA = %w[where exists all select].freeze
      # Functions that pick some of the Bundle entries, as an indexer does.
      PICKS = %w[where first last tail skip take single].freeze
      EXTENSIONS = %w[extension modifierExtension].freeze

      def initialize(origin, steps)
        @origin = origin
        @steps = steps
        @names = []      # the element path the steps follow
        @criteria = []   # the element paths their filters read
        @types = []      # every resource type their filters name
        @type = nil      # the resource type they pick
        @stopped = false # whether the value is no longer an element of the resource
        @entries = false # whether the chain ends at Bundle entries
      end

      def read
        case @origin.shape
        when :bundle then member?(@steps.first, "entry") ? read_entries(@steps.drop(1)) : leave
        when :entries then read_entries(@steps)
        else read_path(@steps)
        end
        Read.new(origin: value_origin, paths:, types: @types.compact.uniq)
      end

      private

      # A chain's own type counts only from the resource itself.
      def value_origin
        type = @origin.type || (@type if @origin.path == "")
        path = at(@names.join(".")) if @origin.path && !@stopped
        Origin.new(shape: @entries ? :entries : :resource, type:, path:, carried: path ? carried : paths)
      end

      def paths
        [(at(@names.join(".")) if @origin.path), *carried].compact.reject(&:empty?).uniq
      end

      def carried
        return @origin.carried unless @origin.path

        [*@origin.carried, *@criteria.map { |path| at(path) }].uniq
      end

      def at(path)
        join(@origin.path, path)
      end

      def join(prefix, path)
        [prefix, path].reject(&:empty?).join(".")
      end

      # A chain that never reaches a resource, like `%q.total` or `%q.entry.count()`, reads the Bundle: no element.
      def leave
        @stopped = true
      end

      # The steps after `entry`: picks, then `resource`. A `where(resource is T)` pick or an `ofType(T)` right
      # after `resource` gives the type. A chain that only picks entries ends at entries, and a variable it
      # defines reads `resource` the same way.
      def read_entries(steps)
        picks = steps.take_while { |step| step[:kind] != :member }
        rest = steps.drop(picks.size)
        filter_type = picks.filter_map { |step| entry_filter_type(step) }.last
        @criteria.concat(picks.flat_map { |step| step[:args] }.flat_map { |arg| criteria_paths(arg) }
                              .filter_map { |path| path[/\Aresource\.(.+)/, 1] })
        return read_resource(rest.drop(1), filter_type) if member?(rest.first, "resource")
        return leave unless rest.empty? && picks.all? { |step| pick?(step) }

        @entries = true
        @type = filter_type
        @types = [filter_type]
      end

      def read_resource(steps, filter_type)
        typed = function?(steps.first, "ofType")
        of_type = type_name(steps.first) if typed
        @type = of_type || filter_type
        @types = [of_type, filter_type]
        read_path(typed ? steps.drop(1) : steps)
      end

      def read_path(steps)
        steps.each do |step|
          case step[:kind]
          when :member then @names << step[:name]
          when :function
            read_function(step, url_in_path: extension_filter(step))
            break leave if STOPS.include?(step[:name])
          end
        end
      end

      # url_in_path: whether the step's `url` condition is already in the path, so it is not listed again.
      def read_function(step, url_in_path:)
        name, args = step.values_at(:name, :args)
        if CRITERIA.include?(name)
          prefix = @names.join(".")
          read = args.flat_map { |arg| criteria_paths(arg) } - (url_in_path ? ["url"] : [])
          @criteria.concat(read.map { |path| join(prefix, path) })
        end
        read_resource_type(args.first) if name == "where" && args.one? && @names.empty?
      end

      # A `where(resourceType = 'T')` on the chain's start picks resources of type `T`: the one it requires,
      # alone or in an `and`, and every one it names in any `and` or `or` branch.
      def read_resource_type(condition)
        @type ||= literals(condition, "resourceType", AND_NODES).first
        @types.concat(literals(condition, "resourceType", [*AND_NODES, "OrExpression"]))
      end

      # Folds an extension filter's url into the path, like `extension[url=X]`, and returns whether it did.
      # A `url = 'X'` inside another chain, like `extension.where(url = 'Y')`, is about a sub-extension.
      def extension_filter(step)
        name, args = step.values_at(:name, :args)
        if name == "extension" && (url = string_literal(args.first))
          @names << "extension[url=#{url}]"
        elsif name == "where" && EXTENSIONS.include?(@names.last) && args.one? &&
              (url = literals(args.first, "url", URL_NODES).first)
          @names[-1] = "#{@names.last}[url=#{url}]"
        end
      end

      # The element paths a `where`, `exists`, `all` or `select` argument reads, relative to its element.
      # `resourceType` isn't an element. A chain starting elsewhere, like `%name` or `now()`, reads only its own
      # start's arguments.
      def criteria_paths(node)
        return [] unless node.is_a?(Hash)

        steps = steps_from(node) { |term| relative_start(term) }
        if steps
          return Chain.new(Origin.resource, steps).read.paths.reject { |path| path.split(".").last == "resourceType" }
        end

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

      # The `T` of `where(resource is T)` or `where(resource.is(T))`.
      def entry_filter_type(step)
        return unless function?(step, "where") && step[:args].one?

        condition = step[:args].first
        subject, type = children(condition)
        return unless subject&.dig("text") == "resource"

        case condition["type"]
        when "TypeExpression" then clean_type(type&.dig("text")) if condition["terminalNodeText"].to_a == ["is"]
        when "InvocationExpression" then called_type(type)
        end
      end

      # The `T` of an `is(T)` call.
      def called_type(invocation)
        return unless invocation&.dig("type") == "FunctionInvocation"

        call = function_step(children(invocation).first)
        type_name(call) if call[:name] == "is"
      end

      def type_name(step)
        clean_type(step[:args].first&.dig("text"))
      end

      def clean_type(text)
        text.to_s.delete("`").delete_prefix("FHIR.")
      end

      def pick?(step)
        step[:kind] == :index || (step[:kind] == :function && PICKS.include?(step[:name]))
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
