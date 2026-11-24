# frozen_string_literal: true

require_relative "expression"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    ItemUse = Data.define(:link_id, :text, :extension, :reads)

    # One form item, or the questionnaire root, using a source through an expression of `extension`, with the
    # element paths the expression reads. A use on the root has no `link_id` or `text`: the root's `text` is its
    # narrative.
    class ItemUse
      VARIABLE = "variable"
      ROOT_LABEL = "The whole form"

      # What an item does with the source, by the extension whose expression reads it.
      ACTIONS = {
        "initialExpression" => "pre-fills the answer",
        "calculatedExpression" => "calculates the answer",
        "itemPopulationContext" => "sets the population context",
        "enableWhenExpression" => "shows or hides the item",
        "answerExpression" => "lists the answer options",
        "candidateExpression" => "suggests answers",
        "contextExpression" => "gives context for answering",
        "itemExtractionContext" => "sets the extraction context",
        "templateExtract" => "its answers fill the template"
      }.freeze
      private_constant :ROOT_LABEL, :ACTIONS

      # The use of an expression on `node`, the questionnaire root's or an item's Hash.
      def self.of(node, extension, reads: [])
        text = node["text"]
        new(link_id: node["linkId"], text: (text if text.is_a?(String)), extension:, reads:)
      end

      def initialize(link_id: nil, text: nil, extension: nil, reads: [])
        super
      end

      # The item's text with its Markdown escaped, else its linkId; a use with neither is on the questionnaire root.
      def label
        words = text.to_s.split.join(" ")
        return words.gsub(/[*_`\[\]]/) { |match| "\\#{match}" } unless words.empty?

        link_id&.to_s || ROOT_LABEL
      end

      # What the use does to the item, else the extension's name; `nil` without an extension.
      def action
        ACTIONS.fetch(extension) { extension }
      end
    end

    # One questionnaire, as a Hash. Its nodes are the root and the items, which define variables and hold
    # expressions; a variable is visible on its node and the items under it.
    class Form
      VARIABLE_URL = "http://hl7.org/fhir/StructureDefinition/variable"
      ASSEMBLE_CONTEXT_URL = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-assembleContext"
      FHIRPATH = "text/fhirpath"
      QUERY = "application/x-fhir-query"

      attr_reader :root

      def self.list(value)
        value.is_a?(Array) ? value : []
      end

      def initialize(questionnaire)
        @root = questionnaire
        @expressions = {}
        log_assemble_contexts
        log_forward_references
      end

      def url = root["url"]
      # The `id` stands in for a missing `url`, so forms without one stay apart.
      def id = (root["id"] unless url)
      def version = root["version"]
      def title = root["title"]
      def label = title || url || id || "Untitled questionnaire"
      # Sources of one version of one form have the same key.
      def key = [url, id, version]

      def root?(node)
        node.equal?(root)
      end

      # The root and every item, in document order.
      def nodes
        [root, *descendants(root)]
      end

      # The node's own extensions with this url.
      def extensions(node, url)
        list(node["extension"]).select { |extension| extension["url"] == url }
      end

      def contained(id)
        list(root["contained"]).find { |resource| resource["id"] == id }
      end

      # `[name, expression, node]` for each `variable` extension in this language, in document order.
      def variables(language)
        nodes.flat_map { |node| variables_on(node, language).map { |name, text| [name, text, node] } }
      end

      # The ItemUses of `%name`, bound to `origin` on `node`: one per expression on the node or an item under it
      # that reads the name, directly or through FHIRPath variables, in document order. The block says which
      # resource types count. A variable definition is not a use: the items that read the variable are.
      def uses(name, node, origin, &accept)
        walk(node, { name => origin }, accept).uniq
      end

      # The resource types the form's chains from `%name` name, when the name is a Bundle on `node`.
      def types(name, node)
        [node, *descendants(node)].flat_map { |under| expressions(under) }
                                  .flat_map { |_extension, expression| expression.reads({ name => Origin.bundle }) }
                                  .flat_map(&:types).uniq
      end

      private

      # Scope is recursion: `env`, `{ name => Origin }`, holds what is visible on the node, and each FHIRPath
      # variable that reads one of its names adds itself for the node's own expressions and the items under it.
      def walk(node, env, accept)
        env = variables_on(node, FHIRPATH).reduce(env) do |bound, (name, text)|
          origin = variable_origin(fhirpath(text).reads(bound), accept)
          origin ? bound.merge(name => origin) : bound
        end
        uses_on(node, env, accept) + list(node["item"]).flat_map { |item| walk(item, env, accept) }
      end

      # The Origin a variable is bound to: that of the read it stands for, which also carries what the other
      # chains of its expression read, like the `%name` chain in a `where(id in %name...)`.
      def variable_origin(reads, accept)
        read = variable_read(reads, accept)
        return unless read

        others = (reads - [read]).select { |other| accept.call(other.origin.type) }.flat_map(&:paths)
        read.origin.with(carried: (read.origin.carried + others).uniq)
      end

      # The read a variable stands for: the first that counts, one still at an element before one that left. A
      # variable that picks several types, like `where(intent = 'order' or resourceType = 'Medication')`, reads the
      # resource untyped, which `accept` may reject; it still stands for the resource, so typed chains from it count.
      def variable_read(reads, accept)
        counted = reads.select { |read| accept.call(read.origin.type) }
        counted.find { |read| read.origin.path } || counted.first ||
          (reads.find { |read| read.origin.type.nil? && read.origin.path == "" } unless accept.call(nil))
      end

      def uses_on(node, env, accept)
        expressions(node).filter_map do |extension, expression|
          next if extension == ItemUse::VARIABLE

          reads = expression.reads(env).select { |read| accept.call(read.origin.type) }
          ItemUse.of(node, extension, reads: reads.flat_map(&:paths).uniq) if reads.any?
        end
      end

      # `[extension, Expression]` for each FHIRPath expression in the node's own extensions and their
      # sub-extensions, not in nested items. `extension` is the short name, like `initialExpression`.
      def expressions(node)
        list(node["extension"]).flat_map do |extension|
          name = extension["url"].to_s.split("/").last.to_s.delete_prefix("sdc-questionnaire-")
          expression_texts(extension).map { |text| [name, fhirpath(text)] }
        end
      end

      def expression_texts(extension)
        value = extension["valueExpression"]
        own = value && value["language"] == FHIRPATH && value["expression"] ? [value["expression"]] : []
        own + list(extension["extension"]).flat_map { |sub_extension| expression_texts(sub_extension) }
      end

      # Each expression is parsed once, however many sources and variables read it.
      def fhirpath(text)
        @expressions[text] ||= Expression.new(text)
      end

      # `[name, expression]` for each of the node's `variable` extensions in this language.
      def variables_on(node, language)
        extensions(node, VARIABLE_URL).filter_map { |extension| extension["valueExpression"] }
                                      .select { |value| value["language"] == language }
                                      .map { |value| [value["name"], value["expression"].to_s] }
      end

      def descendants(node)
        list(node["item"]).flat_map { |item| [item, *descendants(item)] }
      end

      def list(value)
        Form.list(value)
      end

      # A module form gets its `assembleContext` variables from the form it is assembled into, so the items that
      # read them are traced in the assembled form only.
      def log_assemble_contexts
        names = extensions(root, ASSEMBLE_CONTEXT_URL).filter_map { |extension| extension["valueString"] }
        return if names.empty?

        names &= nodes.flat_map { |node| expressions(node) }.flat_map { |_extension, expression| expression.references }
        return if names.empty?

        QuestionnaireUsage.log("#{label} reads #{names.join(", ")} from the form it is assembled into: trace the " \
                               "assembled form for their item uses")
      end

      # The order of `variable` extensions counts: a variable can use only those defined before it, so a use of
      # a later variable of the same node is not traced.
      def log_forward_references
        nodes.each do |node|
          variables = variables_on(node, FHIRPATH)
          later = variables.map(&:first)
          variables.each do |name, text|
            later.shift
            used = fhirpath(text).references & later
            next if used.empty?

            QuestionnaireUsage.log("untraced #{label} variable #{name} on #{root?(node) ? "root" : node["linkId"]}: " \
                                   "it uses #{used.join(", ")}, defined after it")
          end
        end
      end
    end
  end
end
