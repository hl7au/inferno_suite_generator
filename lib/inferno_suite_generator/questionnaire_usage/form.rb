# frozen_string_literal: true

require_relative "expression"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    ItemUse = Data.define(:link_id, :text, :extension, :reads)

    # One item, or the questionnaire root, using a source.
    class ItemUse
      VARIABLE = "variable"
      ROOT_LABEL = "The whole form"

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

      def self.of(node, extension, reads: [])
        text = node["text"]
        new(link_id: node["linkId"], text: (text if text.is_a?(String)), extension:, reads:)
      end

      def initialize(link_id: nil, text: nil, extension: nil, reads: [])
        super
      end

      def label
        words = text.to_s.split.join(" ")
        return words.gsub(/[*_`\[\]]/) { |match| "\\#{match}" } unless words.empty?

        link_id&.to_s || ROOT_LABEL
      end

      def action
        ACTIONS.fetch(extension) { extension }
      end
    end

    # One questionnaire, as a Hash.
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
      def id = (root["id"] unless url)
      def version = root["version"]
      def title = root["title"]
      def label = title || url || id || "Untitled questionnaire"
      def key = [url, id, version]

      def root?(node)
        node.equal?(root)
      end

      def nodes
        [root, *descendants(root)]
      end

      def extensions(node, url)
        list(node["extension"]).select { |extension| extension["url"] == url }
      end

      def contained(id)
        list(root["contained"]).find { |resource| resource["id"] == id }
      end

      def variables(language)
        nodes.flat_map { |node| variables_on(node, language).map { |name, text| [name, text, node] } }
      end

      def uses(name, node, origin, &accept)
        walk(node, { name => origin }, accept).uniq
      end

      def types(name, node)
        [node, *descendants(node)].flat_map { |under| expressions(under) }
                                  .flat_map { |_extension, expression| expression.reads({ name => Origin.bundle }) }
                                  .flat_map(&:types).uniq
      end

      private

      def walk(node, env, accept)
        env = variables_on(node, FHIRPATH).reduce(env) do |bound, (name, text)|
          origin = variable_origin(fhirpath(text).reads(bound), accept)
          origin ? bound.merge(name => origin) : bound
        end
        uses_on(node, env, accept) + list(node["item"]).flat_map { |item| walk(item, env, accept) }
      end

      def variable_origin(reads, accept)
        read = variable_read(reads, accept)
        return unless read

        others = (reads - [read]).select { |other| accept.call(other.origin.type) }.flat_map(&:paths)
        read.origin.with(carried: (read.origin.carried + others).uniq)
      end

      def variable_read(reads, accept)
        reads.find { |read| accept.call(read.origin.type) } ||
          (reads.find { |read| read.origin.type.nil? && read.origin.path == "" } unless accept.call(nil))
      end

      def uses_on(node, env, accept)
        expressions(node).filter_map do |extension, expression|
          next if extension == ItemUse::VARIABLE

          reads = expression.reads(env).select { |read| accept.call(read.origin.type) }
          ItemUse.of(node, extension, reads: reads.flat_map(&:paths).uniq) if reads.any?
        end
      end

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

      def fhirpath(text)
        @expressions[text] ||= Expression.new(text)
      end

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

      def log_assemble_contexts
        names = extensions(root, ASSEMBLE_CONTEXT_URL).filter_map { |extension| extension["valueString"] }
        return if names.empty?

        names &= nodes.flat_map { |node| expressions(node) }.flat_map { |_extension, expression| expression.references }
        return if names.empty?

        QuestionnaireUsage.log("#{label} reads #{names.join(", ")} from the form it is assembled into: trace the " \
                               "assembled form for their item uses")
      end

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
