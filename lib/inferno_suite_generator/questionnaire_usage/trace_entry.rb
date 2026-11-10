# frozen_string_literal: true

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

      # The use of an expression on `item`, the questionnaire root or an item, as a Hash.
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
      attr_reader :form, :name, :item_uses

      # form: a FormHeader.
      def initialize(form:, name:, item_uses: [])
        @form = form
        @name = name
        @item_uses = item_uses
      end

      # The FhirQuery of a query or an `_include`, else `nil`.
      def query; end

      # A source no item uses is left out, unless a subclass says otherwise.
      def shown?
        item_uses.any?
      end

      # The parameters of the search it makes, or `nil` when it makes no search.
      def search_params; end

      # The request its source makes, which its request test makes too: `:read`, `:search`, `:include` (a search
      # of the query's type), `:create` or `:patch`; `nil` when it makes none.
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
          super || includes.any?
        end

        # A search that selects by no parameter has no test to make it.
        def request
          return :read if read?

          :search if query.search_params.any?
        end

        def search_params
          query.search_params unless read?
        end

        def heading(resource)
          action = read? ? "reads one #{resource} by id" : "searches #{resource} resources"
          "**Query #{name}**: #{action}"
        end

        def unused_line
          "No item reads its results; it fetches #{includes.join(", ")} through _include"
        end

        private

        def read?
          query.read?
        end

        def includes
          query.includes
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
        # template_codes: the template's codes as `system|code`; patch: whether it is a FHIRPath Patch.
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
  end
end
