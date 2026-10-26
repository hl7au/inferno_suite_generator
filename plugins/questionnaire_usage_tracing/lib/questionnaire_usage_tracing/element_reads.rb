# frozen_string_literal: true

require_relative "forms"
require_relative "usage_section"

module InfernoSuitePlugins
  module QuestionnaireUsageTracing
    # The element paths the form items of one group's entries read, each with
    # the items that read it, by questionnaire. The Must Support test lists
    # the ones the group checks, and the group summary the ones it does not:
    #
    #   - **GP Chronic Condition Management Plan**
    #     - **birthDate**: Date of birth, Age
    #
    # Elements come in the order the form first reads them. Uses that only
    # define a variable are left out, as in `ItemLines`.
    class ElementReads
      MAX_ITEMS = 10

      def initialize(entries, group)
        @must_support = MustSupport.new(group)
        @forms = Forms.new(entries.select { |entry| UsageSection.shown?(entry) })
      end

      # The nested list of the elements the group's tests check, or with
      # `checked: false` the ones they do not; "" when there are none.
      def list(checked:)
        @forms.flat_map do |title, entries|
          elements = elements(entries).select { |_label, (path, _items)| @must_support.checked?(path) == checked }
          next [] if elements.empty?

          ["- **#{title}**", *elements.map { |label, (_path, items)| "  - **#{label}**: #{items_text(items)}" }]
        end.join("\n")
      end

      private

      # `{ shown label => [first trace path, item labels] }`.
      def elements(entries)
        usages(entries).each_with_object({}) do |usage, by_label|
          item = ItemLines.label(usage)
          usage[:reads].to_a.each do |path|
            items = (by_label[@must_support.shown(path)] ||= [path, []]).last
            items << item unless items.include?(item)
          end
        end
      end

      # :reek:UtilityFunction
      def usages(entries)
        entries.flat_map { |entry| entry[:used_in].to_a }
               .reject { |usage| ItemLines::HIDDEN_USES.include?(usage[:extension]) }
      end

      # Up to `MAX_ITEMS` labels, then a count of the rest.
      # :reek:UtilityFunction
      def items_text(items)
        more = items.size - MAX_ITEMS
        [items.first(MAX_ITEMS).join(", "), ("and #{more} more" if more.positive?)].compact.join(", ")
      end
    end

    # The "Used in questionnaires" Markdown for a group's Must Support test:
    # the elements it checks that form items read.
    class MustSupportSection
      def initialize(entries, group)
        @group = group
        @list = ElementReads.new(entries, group).list(checked: true)
      end

      def empty?
        @list.empty?
      end

      def markdown
        "#{[UsageSection::HEADING, "", intro, "", @list].join("\n")}\n"
      end

      private

      def intro
        "Items in these questionnaires read Must Support elements of #{@group.resource}. A form can pre-fill " \
          "an item only if the server returns the elements it reads."
      end
    end
  end
end
