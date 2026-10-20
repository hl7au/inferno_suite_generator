# frozen_string_literal: true

require_relative "profile_matcher"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # The "Used in questionnaires" Markdown for one group's trace entries, one
    # `###` heading per questionnaire. Each entry says what the source is, an
    # x-fhir-query says whether the group tests the same search, and a table
    # lists the items that use it, what for, and the element paths they read.
    # Paths the profile neither marks Must Support nor requires get a ⚠️. It
    # never shows FHIRPath expressions.
    #
    # The group template puts the description inside a Ruby `%( ... )`
    # literal, so `to_s` escapes `\`, `(`, `)` and `#{`, `#@`, `#$`.
    class UsageSection
      MAX_ROWS = 25
      WARNING = "⚠️"

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
        "variable" => "defines a variable",
        "itemExtractionContext" => "sets the extraction context",
        "templateExtract" => "is extracted from its answers"
      }.freeze

      def initialize(entries, group)
        @entries = entries
        @group = group
        @must_support = MustSupport.new(group)
      end

      def to_s
        escape(markdown)
      end

      def markdown
        lines = ["## Used in questionnaires", "", intro]
        @entries.group_by { |entry| entry[:questionnaire_title] || entry[:questionnaire_url] }.each do |title, entries|
          lines.push("", "### #{title}", *entries.flat_map { |entry| ["", entry_text(entry)] })
        end
        "#{lines.join("\n")}\n"
      end

      private

      def intro
        "The IG's questionnaires below use #{@group.profile_name || @group.resource} resources. An item is " \
          "pre-populated only when the resources the server returns hold the elements it reads. #{WARNING} marks " \
          "elements that are neither Must Support nor required by the profile, so this group does not check " \
          "that the server returns them."
      end

      # The entry's paragraphs and table, separated by blank lines.
      def entry_text(entry)
        [heading(entry), search(entry), *items(entry), coverage(entry)].compact.join("\n\n")
      end

      def heading(entry)
        name = "`#{entry[:name]}`"
        case entry[:source]
        when "query" then "**Query #{name}**: `#{entry[:query]}`"
        when "include" then "**Included by query #{name}** through `_include=#{entry[:include]}`: `#{entry[:query]}`"
        when "launch_context" then "**Launch context #{name}**: the #{@group.resource} the form is opened for."
        when "template_extract" then "**Extraction template #{name}**: #{template_action(entry)}"
        end
      end

      def template_action(entry)
        return "updates an existing #{@group.resource} with a FHIRPath Patch." if entry[:patch]

        codes = entry[:template_codes].to_a.map { |code| "`#{code}`" }
        "creates a new #{@group.resource}#{" with code #{codes.join(", ")}" unless codes.empty?} from the answers."
      end

      def search(entry)
        SearchCheck.new(entry[:query], @group).line if entry[:source] == "query"
      end

      def items(entry)
        rows = ItemRows.new(entry[:used_in].to_a).rows
        return [unused(entry)] if rows.empty?

        table = ["| Item | Use | Reads |", "| --- | --- | --- |", *rows.first(MAX_ROWS).map { |row| table_row(row) }]
        more = rows.size - MAX_ROWS
        [table.join("\n"), (more.positive? ? "…and #{more} more items, listed in `plugins.yml`." : nil)].compact
      end

      def unused(entry)
        case entry[:source]
        when "query"
          includes = QuerySearch.includes(entry[:query]).map { |value| "`#{value}`" }
          fetch = " It is there to fetch #{includes.join(", ")} through `_include`." unless includes.empty?
          "No item reads the #{@group.resource} resources it returns.#{fetch}"
        when "include" then "No item reads the included #{@group.resource} resources."
        when "template_extract" then "It is extracted from the answers of the whole form."
        else "No item reads it."
        end
      end

      def table_row(row)
        reads = row[:reads].map { |path| read_label(path) }
        cells = [item_label(row), row[:uses].map { |use| USES.fetch(use) { "`#{use}`" } }.join(", "),
                 reads.empty? ? "—" : reads.join(", ")]
        "| #{cells.join(" | ")} |"
      end

      def item_label(row)
        ["`#{row[:link_id]}`", row[:text].to_s.split.join(" ").gsub("|", "\\|")].reject(&:empty?).join(" ")
      end

      def read_label(path)
        label = @must_support.label(path)
        @must_support.covered?(label) ? "`#{label}`" : "`#{label}` #{WARNING}"
      end

      def coverage(entry)
        labels = entry[:elements_read].to_a.map { |path| @must_support.label(path) }.uniq
        return if labels.empty?

        missing = labels.reject { |label| @must_support.covered?(label) }
        return "✅ Every element it reads is Must Support or required." if missing.empty?

        "#{WARNING} Neither Must Support nor required: #{missing.map { |label| "`#{label}`" }.join(", ")}."
      end

      def escape(text)
        text.gsub(/[\\()]|#[{@$]/) { |match| "\\#{match}" }
      end

      # The usages of one entry merged into one row per item, in document
      # order: `{ link_id:, text:, uses:, reads: }`.
      class ItemRows
        def initialize(usages)
          @usages = usages
        end

        def rows
          @usages.group_by { |usage| usage[:link_id] }.map do |link_id, usages|
            { link_id:, text: usages.first[:text], uses: usages.filter_map { |usage| usage[:extension] }.uniq,
              reads: usages.flat_map { |usage| usage[:reads].to_a }.uniq }
          end
        end
      end
    end

    # Whether a group tests a search by the same parameters as an x-fhir-query,
    # in any order.
    class SearchCheck
      def initialize(query, group)
        @names = QuerySearch.params(query)
        @tested = group.searches.to_a.map { |search| search[:names] }
      end

      # A ✅ or ⚠️ line, or `nil` when the query selects by no parameter.
      def line
        return if @names.empty?

        same = @tested.find { |names| names.to_set == @names.to_set }
        return "✅ This group tests the same search: #{label(same)}." if same

        "#{UsageSection::WARNING} This group does not test a search by #{label(@names)}.#{others}"
      end

      private

      def others
        " It tests #{@tested.map { |names| label(names) }.join(", ")}." unless @tested.empty?
      end

      def label(names)
        "`#{names.join(" + ")}`"
      end
    end

    # The element paths a group's profile marks Must Support or requires, so
    # its Must Support or validation tests check them.
    #
    # Trace paths name an extension as `extension[url=U]`. `label` writes one
    # the profile slices as Must Support as `extension:sliceName`, like the
    # profile does. A path inside such an extension counts as checked, since
    # the extension's own profile defines what it holds.
    class MustSupport
      ALWAYS_PRESENT = %w[id].freeze
      EXTENSION_URL = /\A((?:modifierE|e)xtension)\[url=(.+)\]\z/
      EXTENSION_SLICE = /\A(?:modifierE|e)xtension:/

      def initialize(group)
        must_supports = group.must_supports || {}
        @paths = checked_paths(must_supports[:elements].to_a, group.mandatory_elements.to_a)
        @slices = must_supports[:extensions].to_a.to_h { |extension| slice(extension) }
      end

      def label(path)
        segments(path).each_with_object([]) do |segment, done|
          _, member, url = segment.match(EXTENSION_URL).to_a
          done << (@slices[[done.join("."), member, url]] || segment)
        end.join(".")
      end

      def covered?(label)
        ALWAYS_PRESENT.include?(label) || @paths.include?(label) ||
          segments(label).any? { |segment| segment.match?(EXTENSION_SLICE) }
      end

      private

      # Must Support element paths are relative, like `value[x]:valueQuantity.value`;
      # mandatory ones start with the type, like `Observation.status`.
      def checked_paths(elements, mandatory)
        paths = elements.map { |element| element[:path] } + mandatory.map { |path| path.split(".", 2).last }
        paths.compact.to_set { |path| plain(path) }
      end

      # `[[parent path, member, url], "extension:sliceName"]` for an extension
      # with an id like `Patient.address.extension:foo`.
      def slice(extension)
        parent, _, segment = extension[:id].to_s.split(".", 2).last.to_s.rpartition(".")
        [[plain(parent), segment.split(":").first, extension[:url]], segment]
      end

      # A snapshot path without `[x]` and slice names, as trace paths are.
      def plain(path)
        path.gsub("[x]", "").gsub(/:[^.]+/, "")
      end

      # Dot-separated steps, keeping the dots inside `[url=...]` together.
      def segments(path)
        path.scan(/(?:[^.\[]+|\[[^\]]*\])+/)
      end
    end

    # Reads the search parameters of an x-fhir-query.
    module QuerySearch
      # Parameters that shape the result instead of selecting resources.
      RESULT_PARAMS = %w[_sort _include _revinclude _count _elements _summary _total _contained _containedType].freeze

      module_function

      # The parameter names that select resources, without modifiers.
      def params(query)
        pairs(query).map { |name, _value| name.split(":").first }.uniq - RESULT_PARAMS
      end

      # The `_include` values, like `PractitionerRole:location`.
      def includes(query)
        pairs(query).filter_map { |name, value| value if name.split(":").first == "_include" }
      end

      def pairs(query)
        query.to_s.split("?", 2)[1].to_s.split("&").map do |pair|
          pair.split("=", 2).map { |part| ProfileMatcher::Codes.decode(part.to_s) }
        end
      end
    end
  end
end
