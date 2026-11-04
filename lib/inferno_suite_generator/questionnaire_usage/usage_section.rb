# frozen_string_literal: true

require_relative "forms"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # A "Used in questionnaires" list of trace entries for one group: the
    # questionnaires, the sources in each that link to the profile, and the
    # items that use each source. It uses only bold and plain text, since
    # Inferno shows tables without borders and raw HTML as text.
    #
    # The tracing shows one per test, with the entries whose requests the test
    # makes, and one in the group summary, with the entries no test makes.
    #
    # Only `TraceEntry#shown?` entries are listed, each with its `item_uses`.
    # Element paths the profile neither marks Must Support nor requires are
    # marked "(not checked)".
    class UsageSection
      HEADING = "## Used in questionnaires"
      NOT_CHECKED = "(not checked)"

      # search_check: whether a query says how the group's search tests
      # compare to it, which only the group summary needs.
      # checked_by: the groups whose tests can check the elements. A test can
      # make the request of entries traced for several groups of one type.
      def initialize(entries, group, intro: nil, search_check: false, checked_by: [group])
        @group = group
        @intro = intro
        @search_check = search_check
        @must_support = AnyMustSupport.new(checked_by)
        @forms = Forms.new(entries)
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
        @forms.flat_map do |title, entries|
          ["- **#{title}**", *entries.flat_map { |entry| entry_lines(entry) }]
        end.join("\n")
      end

      private

      def entry_lines(entry)
        ["  - #{entry.heading(@group.resource)}", *details(entry).map { |line| "    - #{line}" }]
      end

      def details(entry)
        query = entry.query
        params = entry.search_params if @search_check
        search = SearchCheck.new(params, @group).line if params
        [query && "Request: #{query}", search, *items(entry)].compact
      end

      def items(entry)
        uses = entry.item_uses
        uses.empty? ? [entry.unused_line] : ItemLines.new(uses, @must_support).lines
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
      def initialize(usages, must_support)
        @items = usages.group_by { |usage| usage[:link_id] }.values
        @must_support = must_support
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
        shown = @must_support.shown(path)
        @must_support.checked?(path) ? shown : "#{shown} #{UsageSection::NOT_CHECKED}"
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

    # The element paths a group's profile marks Must Support or requires, so
    # its Must Support or validation tests check them.
    #
    # Trace paths name an extension as `extension[url=U]`. `label` writes one
    # the profile slices as Must Support as `extension:sliceName`, like the
    # profile does. A path inside such an extension counts as checked, since
    # the extension's own profile defines what it holds.
    #
    # A trace path names a choice element by its type, like `valueQuantity`,
    # where the profile has `value[x]`, so `covered?` compares it as `value`.
    class MustSupport
      ALWAYS_PRESENT = %w[id].freeze
      EXTENSION_URL = /\A((?:modifierE|e)xtension)\[url=(.+)\]\z/
      EXTENSION_SLICE = /\A(?:modifierE|e)xtension:/

      def initialize(group)
        must_supports = group.must_supports || {}
        paths = element_paths(must_supports, group.mandatory_elements.to_a)
        @paths = paths.to_set { |path| plain(path) }
        @choices = choice_paths(paths)
        @slices = must_supports[:extensions].to_a.to_h { |extension| slice(extension) }
      end

      def label(path)
        segments(path).each_with_object([]) do |segment, done|
          _, member, url = segment.match(EXTENSION_URL).to_a
          done << (@slices[[done.join("."), member, url]] || segment)
        end.join(".")
      end

      def covered?(label)
        ALWAYS_PRESENT.include?(label) || @paths.include?(without_choice_types(label)) ||
          segments(label).any? { |segment| segment.match?(EXTENSION_SLICE) }
      end

      # The label with an extension the profile does not slice shortened to
      # the last part of its URL, like `extension[individual-pronouns]`.
      def shown(path)
        label(path).gsub(%r{\[url=(?:[^\]]*/)?([^\]/]+)\]}, '[\1]')
      end

      # Whether the group's tests check the trace path.
      def checked?(path)
        covered?(label(path))
      end

      private

      # Must Support element and slice paths are relative, like
      # `value[x]:valueQuantity.value` or `onset[x]` for an `onsetDateTime`
      # type slice; mandatory ones start with the type, like `Observation.status`.
      def element_paths(must_supports, mandatory)
        elements = must_supports[:elements].to_a + must_supports[:slices].to_a
        (elements.map { |element| element[:path] } + mandatory.map { |path| path.split(".", 2).last }).compact
      end

      # `[parent path, name]` for each choice element, like `["", "value"]`
      # for `value[x]:valueQuantity.value`.
      def choice_paths(paths)
        paths.filter_map do |path|
          parent, _, name = plain(path[/\A.*?\[x\]/]).rpartition(".") if path.include?("[x]")
          [parent, name] if name
        end.to_set
      end

      # The label with each segment that names a choice element by its type,
      # like `valueQuantity` or `effectiveDateTime`, written as the element.
      def without_choice_types(label)
        segments(label).each_with_object([]) do |segment, done|
          done << (choice_name(done.join("."), segment) || segment)
        end.join(".")
      end

      def choice_name(parent, segment)
        @choices.find { |choice_parent, name| choice_parent == parent && segment.match?(/\A#{name}[A-Z]/) }&.last
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

    # The elements any of several groups checks. A path shows as the group that
    # checks it names it, so a slice one profile defines keeps its name.
    class AnyMustSupport
      def initialize(groups)
        @must_supports = groups.map { |group| MustSupport.new(group) }
      end

      def shown(path)
        checking = @must_supports.find { |must_support| must_support.checked?(path) }
        (checking || @must_supports.first).shown(path)
      end

      def checked?(path)
        @must_supports.any? { |must_support| must_support.checked?(path) }
      end
    end
  end
end
