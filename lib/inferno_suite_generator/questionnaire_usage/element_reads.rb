# frozen_string_literal: true

require_relative "forms"
require_relative "usage_section"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # The element paths the form items of one group's Delivery::Placements read,
    # each with the items that read it, by questionnaire. The Must Support test
    # lists the ones the group checks, and the group summary the ones no test
    # checks:
    #
    #   - **GP Chronic Condition Management Plan**
    #     - **birthDate**: Date of birth, Age
    #
    # Elements come in the order the form first reads them.
    class ElementReads
      MAX_ITEMS = 10

      def initialize(placements)
        @forms = Forms.new(placements)
      end

      # The nested list of the elements the group's Must Support test lists; ""
      # when there are none.
      def must_support
        list(&:must_support_reads)
      end

      # The nested list of the elements no test checks; "" when there are none.
      def not_checked
        list { |placement| placement.reads.reject { |_path, read| read.checked } }
      end

      private

      # The block gives the `{ path => ElementRead }` to list for a placement.
      def list(&reads)
        @forms.flat_map do |title, placements|
          elements = elements(placements, reads)
          next [] if elements.empty?

          ["- **#{title}**", *elements.map { |label, items| "  - **#{label}**: #{items_text(items)}" }]
        end.join("\n")
      end

      # `{ element label => item labels }`.
      def elements(placements, reads)
        placements.each_with_object({}) do |placement, by_label|
          listed = reads.call(placement)
          placement.entry.item_uses.each { |usage| add_item(by_label, usage, listed) }
        end
      end

      # :reek:UtilityFunction
      def add_item(by_label, usage, listed)
        item = ItemLines.label(usage)
        listed.values_at(*usage[:reads].to_a).compact.each do |read|
          items = (by_label[read.label] ||= [])
          items << item unless items.include?(item)
        end
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
      def initialize(placements, group)
        @group = group
        @list = ElementReads.new(placements).must_support
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
