# frozen_string_literal: true

require "fhir_models"
require "uri"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    ItemUse = Data.define(:link_id, :text, :extension, :reads)

    # One form item, or the questionnaire root, reading a source through an expression of `extension`.
    # A use on the root has no `link_id` or `text`: the root's `text` is its narrative.
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
      private_constant :VARIABLE, :ROOT_LABEL, :ACTIONS

      # The use of an expression on `item`, the questionnaire root's or an item's Hash.
      def self.of(item, extension, reads: [])
        item_text = item["text"]
        new(link_id: item["linkId"], text: (item_text if item_text.is_a?(String)), extension:, reads:)
      end

      # Whether the expression only defines a variable: the items that read the variable are what use the source.
      def self.variable?(extension)
        extension == VARIABLE
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

    FormHeader = Data.define(:url, :id, :version, :title)

    # The questionnaire a trace entry was traced in. An `id` stands in for a missing `url`.
    class FormHeader
      def initialize(url: nil, id: nil, version: nil, title: nil)
        super
      end

      # Entries of one version of one form have the same key.
      def key
        [url, id, version]
      end

      def label
        title || url || id || "Untitled questionnaire"
      end
    end

    # One questionnaire source, shared by the groups whose profile it links to. Each kind is a subclass that
    # says how it's shown and requested; `Sources` traces them. Entries are equal only when they are the same
    # object, so equal sources in a form stay apart.
    class TraceEntry
      attr_reader :header, :name, :item_uses

      def initialize(header:, name:, item_uses: [])
        @header = header
        @name = name
        @item_uses = item_uses
      end

      # The FhirQuery of a query or an `_include`, else `nil`.
      def query; end

      # A source no item uses is left out, unless a subclass says otherwise.
      def shown?
        item_uses.any?
      end

      # The request its source makes, which its request test makes too: `:read`, `:search`, `:include` (a search
      # of the query's type, made by a group of that type), `:create` or `:patch`; `nil` when it makes none.
      def request; end

      # The line a section shows for an entry with no item uses.
      def unused_line; end

      # A `launchContext` resource, like `%patient`.
      class LaunchContext < TraceEntry
        def request = :read

        def heading(resource)
          "**Launch context #{name}**: the #{resource} the form is opened for"
        end
      end

      # An x-fhir-query variable: a search, or a read of one resource by id.
      class Query < TraceEntry
        attr_reader :query

        def initialize(query:, **entry)
          super(**entry)
          @query = query
        end

        # A query that fetches other resources through `_include` is shown even
        # when no item reads its own results.
        def shown?
          super || query.includes.any?
        end

        # A search that selects by no parameter has no test to make it.
        def request
          return :read if query.read?

          :search if query.search_params.any?
        end

        def heading(resource)
          action = query.read? ? "reads one #{resource} by id" : "searches #{resource} resources"
          "**Query #{name}**: #{action}"
        end

        def unused_line
          "No item reads its results; it fetches #{query.includes.join(", ")} through _include"
        end
      end

      # What a query fetches through one `_include` target. Its request is the
      # query's, so its test is in a group of the query's own type.
      class Include < TraceEntry
        attr_reader :query

        # include: the `_include` value, like `PractitionerRole:location`.
        def initialize(query:, include:, **entry)
          super(**entry)
          @query = query
          @include = include
        end

        def request = :include

        def heading(resource)
          "**Query #{name}**: fetches #{resource} resources through _include=#{@include}"
        end
      end

      # A contained resource a `templateExtract` fills from the answers. It is
      # shown even when it is extracted from the whole form, which no item uses.
      class Template < TraceEntry
        # template_codes: the template's codes as `system|code`.
        def initialize(patch:, template_codes: [], **entry)
          super(**entry)
          @patch = patch
          @template_codes = template_codes
        end

        def shown?
          true
        end

        def request
          @patch ? :patch : :create
        end

        def heading(resource)
          "**Extraction template #{name}**: #{action(resource)}"
        end

        def unused_line
          "Its answers come from the whole form"
        end

        private

        def action(resource)
          return "updates an existing #{resource} with a FHIRPath Patch" if @patch

          codes = @template_codes
          "creates a new #{resource}#{" with code #{codes.join(", ")}" unless codes.empty?} from the answers"
        end
      end
    end

    # The trace entries of every questionnaire, each with the groups its source links to, which share it.
    class Trace
      def initialize
        @entries = {}
        @groups = {}.compare_by_identity
      end

      # Links the entry to the groups; adding it again links more groups.
      def add(groups, entry)
        linked = (@groups[entry] ||= [])
        (groups - linked).each do |group|
          linked << group
          (@entries[group.profile_url] ||= []) << entry
        end
        self
      end

      def entries(group)
        @entries.fetch(group.profile_url) { [] }
      end

      # The groups that share the entry, in the order they were linked.
      def groups(entry)
        @groups.fetch(entry) { [] }
      end

      # `{ profile_url => [TraceEntry] }`, in trace order.
      def to_h
        @entries.transform_values(&:dup)
      end
    end

    # One x-fhir-query, parsed once.
    class FhirQuery
      # The search parameters that can tell the profiles of one type apart.
      CODE_PARAMS = %i[code category].freeze
      # Parameters that shape the result instead of selecting resources.
      RESULT_PARAMS = %w[_sort _include _revinclude _count _elements _summary _total _contained _containedType].freeze
      # One `name=value` pair. A `{{...}}` template can hold `&`, FHIRPath's
      # string concatenation, so it is kept whole.
      PAIR = /(?:\{\{.*?\}\}|[^&])+/
      private_constant :RESULT_PARAMS, :PAIR

      def initialize(text)
        @text = text.to_s
        path, search = @text.split("?", 2)
        @segments = path.to_s.split("/")
        @type_index = @segments.rindex { |segment| FHIR::RESOURCES.include?(segment) }
        @pairs = search.to_s.scan(PAIR).map { |pair| decoded_pair(pair) }
      end

      def to_s
        @text
      end

      # The last path segment that names a resource type, so a compartment search like
      # `Patient/{{%patient.id}}/Observation?...` gives `Observation`; without one, the last segment.
      def resource_type
        @type_index ? @segments[@type_index] : @segments.last
      end

      # Whether an id follows the type, so the query reads one resource instead of giving a Bundle.
      # An operation, like `Patient/{{%patient.id}}/$everything`, gives a Bundle.
      def read?
        return false unless @type_index

        following = @segments[@type_index + 1]
        !following.nil? && !following.start_with?("_", "$") && @segments.none? { |segment| segment.start_with?("$") }
      end

      # The names that select resources, without modifiers. A compartment search, like
      # `Patient/{{%patient.id}}/Observation?code=x`, also selects by `patient`.
      def search_params
        names = @pairs.map { |name, _value| name.split(":").first }
        [*compartment_param, *names].uniq - RESULT_PARAMS
      end

      # The `_include` values of the query's own type, like `PractitionerRole:location` on a PractitionerRole search.
      def includes
        @pairs.filter_map { |name, value| value if own_include?(name, value) }
      end

      # The `[name, value]` pairs of the `_include` parameters `includes` leaves
      # out: `_include:iterate`, and includes from other types.
      def other_includes
        @pairs.select { |name, value| name.start_with?("_include") && !own_include?(name, value) }
      end

      # `{ code: [...], category: [...] }` of `{ system:, code: }`, from `system|code` or `code` values. A comma
      # means OR, and values with a `{{...}}` template are skipped.
      def codes
        CODE_PARAMS.to_h do |param|
          [param, @pairs.select { |name, _value| name == param.to_s }.flat_map { |_name, value| code_values(value) }]
        end
      end

      private

      # `[name, value]`, decoded. A parameter without `=` has the value `""`.
      def decoded_pair(pair)
        name, value = pair.split("=", 2)
        [decode(name.to_s), decode(value.to_s)]
      end

      def own_include?(name, value)
        name == "_include" && value.split(":").first == resource_type
      end

      def compartment_param
        compartment = @segments[@type_index - 2] if @type_index && @type_index >= 2
        compartment.downcase if FHIR::RESOURCES.include?(compartment)
      end

      def code_values(value)
        return [] if value.include?("{{")

        value.split(",").filter_map do |token|
          parts = token.split("|", 2)
          code = parts.last.to_s
          next if code.empty?

          system = parts.first if parts.size == 2
          { system: system.to_s.empty? ? nil : system, code: }
        end
      end

      def decode(text)
        URI.decode_uri_component(text)
      rescue ArgumentError
        text
      end
    end
  end
end
