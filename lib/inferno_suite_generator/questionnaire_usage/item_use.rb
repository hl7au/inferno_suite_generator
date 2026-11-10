# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    ItemUse = Data.define(:link_id, :text, :extension, :reads)

    # One form item, or the questionnaire root, reading a source through an
    # expression. `extension` is the short name of the expression's extension,
    # and `reads` the element paths it reads.
    #
    # An item use on the root, like a root `itemExtractionContext`, has no
    # `link_id` or `text`: every item has a `linkId`, and the root's `text` is its
    # narrative.
    class ItemUse
      VARIABLE = "variable"
      ROOT_LABEL = "The whole form"

      # What an item does with the source, by the short name of the extension
      # whose expression reads it.
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

      # The use of an expression on `item`: the questionnaire root or an item, as
      # a Hash.
      def self.of(item, extension, reads: [])
        item_text = item["text"]
        new(link_id: item["linkId"], text: (item_text if item_text.is_a?(String)), extension:, reads:)
      end

      # Whether an expression of this extension only defines a variable, so the
      # items that read the variable are what use the source, and `Tracer`
      # leaves it out.
      def self.variable?(extension)
        extension == VARIABLE
      end

      def initialize(link_id: nil, text: nil, extension: nil, reads: [])
        super
      end

      # The item's text with its Markdown escaped, or its linkId when it has none.
      # A use with neither is on the questionnaire root.
      def label
        words = text.to_s.split.join(" ")
        return words.gsub(/[*_`\[\]]/) { |match| "\\#{match}" } unless words.empty?

        link_id&.to_s || ROOT_LABEL
      end

      # What the use does to the item, or the extension's name when that isn't
      # known. `nil` when it has no extension.
      def action
        ACTIONS.fetch(extension) { extension }
      end
    end
  end
end
