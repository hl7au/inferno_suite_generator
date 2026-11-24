# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # The items of one form that use one source: actions and element paths, merged per linkId.
    class Use
      attr_reader :label, :actions, :paths

      def initialize(label)
        @label = label
        @actions = []
        @paths = []
      end

      def add(action, paths)
        @actions |= [action]
        @paths |= paths
      end

      # Merges [[key, label, action], chain] readings per item key; the block gives a chain's paths or nil.
      def self.merge(readings)
        merged = {}
        readings.each do |(key, label, action), chain|
          paths = yield(chain)
          (merged[key] ||= new(label)).add(action, paths) if paths
        end
        merged.values
      end

      def reads(source)
        paths.map { |path| Read.new(source, path, label) }
      end
    end

    # One element path an item reads through a source.
    Read = Struct.new(:source, :path, :label) do
      def form = source.form

      def checked_in?(trace) = trace.by_source?(source, path)
    end

    # The form root or one item, with the [action, FHIRPath text] pairs on its extensions and the
    # variables visible on it.
    Node = Struct.new(:key, :label, :expressions, :scope) do
      def readings
        expressions.flat_map { |action, text| [[key, label, action]].product(scope.chains(text)) }
      end
    end

    # One traced Questionnaire, given as a fhir_models resource or a plain Hash.
    class Form
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
      MARKDOWN = /[*_`\[\]]/
      ASSEMBLED = "/sdc-questionnaire-assembleContext"

      attr_reader :title, :ig_resources

      # The IG's forms, one per (url, id-when-no-url, version), same titles told apart by version.
      def self.load(ig_resources)
        forms = ig_resources.get_resources_by_type("Questionnaire").map do |resource|
          new(resource.to_hash, ig_resources)
        end.uniq(&:key)
        repeated = forms.map(&:base_title).tally
        forms.each { |form| form.show_version if repeated[form.base_title] > 1 }.each(&:read_expressions)
      end

      def self.action(url)
        short = url.split("/").last.to_s.delete_prefix("sdc-questionnaire-")
        ACTIONS.fetch(short, short)
      end

      def self.expressions(node)
        QuestionnaireUsage.list(node, "extension").flat_map { |extension| extension_expressions(extension) }
      end

      # A variable definition is not a use; the expressions that read the variable are.
      def self.extension_expressions(extension)
        url = extension["url"].to_s
        return [] if url.end_with?("/variable")

        action = action(url)
        texts(extension).map { |text| [action, text] }
      end

      # FHIRPath expressions on the extension and its sub-extensions.
      def self.texts(extension)
        own = QuestionnaireUsage.text(extension, "valueExpression", "expression")
        own = nil unless QuestionnaireUsage.text(extension, "valueExpression", "language") == "text/fhirpath"
        [own, *QuestionnaireUsage.list(extension, "extension").flat_map { |sub| texts(sub) }].compact
      end

      def self.label(item)
        text = QuestionnaireUsage.text(item, "text")&.gsub(/\s+/, " ")&.strip
        text = item["linkId"].to_s if text.to_s.empty?
        text.gsub(MARKDOWN) { |char| "\\#{char}" }
      end

      def initialize(data, ig_resources)
        @data = data
        @ig_resources = ig_resources
        @title = base_title
        @chains = {}
      end

      def key = [url, url ? nil : field("id"), field("version")]

      def base_title = field("title") || url || field("id") || "Untitled questionnaire"

      def show_version
        version = field("version")
        @title = "#{base_title}, version #{version}" if version
      end

      # Queries, each followed by its includes, then launch contexts, then templates, each in document order.
      def sources
        @sources ||= [*Query.all(self, @data).flat_map { |query| [query, *query.includes] },
                      *QuestionnaireUsage.list(@data, "extension").flat_map do |extension|
                        LaunchContext.from(self, extension)
                      end,
                      *Template.all(self, @data)]
      end

      # Each distinct expression is parsed once per form.
      def chains(text)
        @chains[text] ||= Chain.parse(text)
      end

      # Parses and resolves every expression once, logging untraced variables and assembled-in names.
      def read_expressions = readings

      # [[key, label, action], chain] for every chain that starts at %name.
      def readings_of(name) = readings.fetch(name, [])

      private

      def field(name) = QuestionnaireUsage.text(@data, name)

      def url = field("url")

      # [[key, label, action], chain] for every chain, grouped by the name the chain starts at.
      def readings
        @readings ||= nodes.flat_map(&:readings).group_by { |reading| reading.last.name }
                           .tap { |by_name| log_assembled(by_name.keys) }
      end

      # The root and every item, each with the variables visible on it.
      def nodes
        scope = Scope.new(self).inner(:root, Scope.definitions(@data))
        [Node.new(:root, "The whole form", Form.expressions(@data), scope), *items(@data, scope)]
      end

      def items(parent, outer)
        QuestionnaireUsage.list(parent, "item").flat_map do |item|
          key = item["linkId"]
          scope = outer.inner(key, Scope.definitions(item))
          [Node.new(key, Form.label(item), Form.expressions(item), scope), *items(item, scope)]
        end
      end

      def assembled
        QuestionnaireUsage.list(@data, "extension").select { |extension| extension["url"].to_s.end_with?(ASSEMBLED) }
                          .filter_map { |extension| QuestionnaireUsage.text(extension, "valueString") }
      end

      # A module form reads names that only the form it is assembled into defines.
      def log_assembled(names)
        used = names & assembled
        return if used.empty?

        QuestionnaireUsage.log("#{title} reads #{used.join(", ")} from the form it is assembled into: " \
                               "trace the assembled form for their item uses")
      end
    end
  end
end
