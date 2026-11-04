# frozen_string_literal: true

require_relative "forms"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # A "Used in questionnaires" list of Delivery::Placements for one group: the
    # questionnaires, the sources in each that link to the profile, and the
    # items that use each source. It uses only bold and plain text, since
    # Inferno shows tables without borders and raw HTML as text.
    #
    # The tracing shows one per test, with the entries whose requests the test
    # makes, and one in the group summary, with the entries no test makes.
    #
    # Only `TraceEntry#shown?` entries are listed, each with its `item_uses`.
    # Element paths Delivery found no test checks are marked "(not checked)".
    class UsageSection
      HEADING = "## Used in questionnaires"
      NOT_CHECKED = "(not checked)"

      # search_check: whether a query says how the group's search tests
      # compare to it, which only the group summary needs.
      def initialize(placements, group, intro: nil, search_check: false)
        @group = group
        @intro = intro
        @search_check = search_check
        @forms = Forms.new(placements)
      end

      def empty?
        @forms.empty?
      end

      # The heading, the intro and the list.
      def markdown
        "#{[HEADING, "", @intro, "", list].join("\n")}\n"
      end

      # The nested list alone, one line per string.
      def list
        @forms.flat_map do |title, placements|
          ["- **#{title}**", *placements.flat_map { |placement| entry_lines(placement) }]
        end.join("\n")
      end

      private

      def entry_lines(placement)
        ["  - #{placement.entry.heading(@group.resource)}", *details(placement).map { |line| "    - #{line}" }]
      end

      def details(placement)
        entry = placement.entry
        query = entry.query
        params = entry.search_params if @search_check
        search = SearchCheck.new(params, @group).line if params
        [query && "Request: #{query}", search, *items(placement)].compact
      end

      # :reek:UtilityFunction
      def items(placement)
        entry = placement.entry
        uses = entry.item_uses
        uses.empty? ? [entry.unused_line] : ItemLines.new(uses, placement.reads).lines
      end
    end

    # One list line per item that uses a source, in document order, like
    # `**Height**: pre-fills the answer, shows or hides the item; reads value.value`.
    # An item that uses the source in several extensions gets one line.
    class ItemLines
      MAX = 25
      ROOT_LABEL = "The whole form"

      # What an item does with the source, by the short name of the extension
      # whose expression reads it.
      USES = {
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

      # The item's text, or its linkId when it has none. A usage with neither
      # is on the questionnaire root.
      def self.label(usage)
        text = usage[:text].to_s.split.join(" ")
        return text.gsub(/[*_`\[\]]/) { |match| "\\#{match}" } unless text.empty?

        usage[:link_id]&.to_s || ROOT_LABEL
      end

      # usages: a `TraceEntry#item_uses`.
      # reads: the entry's `Delivery::Placement#reads`.
      def initialize(usages, reads)
        @items = usages.group_by { |usage| usage[:link_id] }.values
        @reads = reads
      end

      # Up to `MAX` lines, then one that counts the rest.
      def lines
        more = @items.size - MAX
        [*@items.first(MAX).map { |usages| line(usages) },
         ("and #{more} more items, listed in questionnaire_usage.yml" if more.positive?)].compact
      end

      private

      # Leaves out a part the item has nothing for.
      def line(usages)
        details = [uses(usages), reads(usages)].compact.join("; ")
        "**#{label(usages.first)}**#{": #{details}" unless details.empty?}"
      end

      def uses(usages)
        names = usages.filter_map { |usage| usage[:extension] }.uniq
        names.map { |name| USES.fetch(name) { name } }.join(", ") unless names.empty?
      end

      def reads(usages)
        paths = usages.flat_map { |usage| usage[:reads].to_a }.uniq
        "reads #{paths.map { |path| read_label(path) }.join(", ")}" unless paths.empty?
      end

      def label(usage)
        self.class.label(usage)
      end

      def read_label(path)
        read = @reads.fetch(path)
        read.checked ? read.label : "#{read.label} #{UsageSection::NOT_CHECKED}"
      end
    end

    # How a group's searches compare to an x-fhir-query that none of its
    # search tests makes, for the group summary.
    class SearchCheck
      # names: the query's `TraceEntry#search_params`.
      def initialize(names, group)
        @names = names
        @tested = group.searches.to_a.map { |search| search[:names] }
      end

      # A line for the list, or `nil` when the query selects by no parameter.
      def line
        return if @names.empty?

        same = @tested.find { |names| names.to_set == @names.to_set }
        return "This group searches by the same parameters, #{label(same)}, but has no test for it" if same

        "A search by #{label(@names)}#{others}"
      end

      private

      def others
        "; this group tests #{@tested.map { |names| label(names) }.join(", ")}" unless @tested.empty?
      end

      def label(names)
        names.join(" + ")
      end
    end
  end
end
