# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # The fixed Markdown strings and list shapes (parent ticket §3.10).
    module Markdown
      reads = "A form can pre-fill an item only if the server returns the elements the item reads."
      not_checked = "Elements marked (not checked) are neither Must Support nor required by the profile, " \
                    "so this group's tests do not check them."

      HEADER = "**Used in questionnaires**"
      # Keyed by the kind of the test that lists the sources, plus the group summary.
      INTROS = {
        "read" => "These questionnaires in the IG read %<resource>s resources as this test does: by id, or as " \
                  "the resource a form is opened for. #{reads} #{not_checked}",
        "must_support" => "Items in these questionnaires read elements of %<resource>s that this group's tests " \
                          "check. #{reads}",
        group: "These questionnaires in the IG read or create %<resource>s resources. The tests that make the " \
               "same requests list the form items that depend on them."
      }.freeze
      BLOCKS = {
        not_tested: ["**Not tested by this group**",
                     "No test in this group makes these requests or writes these resources, so nothing checks " \
                     "what these forms get from them."],
        not_checked: ["**Elements not checked**",
                      "The profile neither marks these elements Must Support nor requires them, so no test checks " \
                      "that the server returns them."]
      }.freeze
      ITEM_CAP = 25
      LABEL_CAP = 10

      def self.section(*parts) = "#{[HEADER, *parts].join("\n\n")}\n"

      def self.block(name, list) = list.empty? ? [] : [*BLOCKS.fetch(name), list]

      def self.capped(labels)
        rest = labels.size - LABEL_CAP
        [labels.first(LABEL_CAP).join(", "), *("and #{rest} more" if rest.positive?)].join(", ")
      end

      def self.sentence(labels)
        *init, last = labels
        init.empty? ? "#{last} test" : "#{init.join(", ")} and #{last} tests"
      end

      def self.source_list(placements, trace)
        by_form(placements.map(&:source)) { |source| source_lines(source, trace) }
      end

      def self.source_lines(source, trace)
        uses = source.uses
        rest = uses.size - ITEM_CAP
        lines = uses.first(ITEM_CAP).map { |use| "    - #{item_line(source, use, trace)}" }
        ["  - #{source.heading}", *lines, *("    - and #{rest} more items" if rest.positive?)]
      end

      def self.item_line(source, use, trace)
        reads = use.paths.map { |path| trace.by_source?(source, path) ? path : "#{path} (not checked)" }
        "**#{use.label}**: #{use.actions.join(", ")}#{"; reads #{reads.join(", ")}" unless reads.empty?}"
      end

      # One line per element and form, with the labels of the items that read it.
      def self.element_list(reads)
        rows = reads.group_by { |read| [read.form, read.path] }.values.map do |same|
          Read.new(same.first.source, same.first.path, capped(same.map(&:label).uniq))
        end
        by_form(rows) { |row| "  - **#{row.path}**: #{row.label}" }
      end

      # "- **<title>**" for each form, followed by the lines of its entries.
      def self.by_form(entries, &)
        entries.group_by(&:form).map { |form, same| ["- **#{form.title}**", *same.flat_map(&)].join("\n") }
               .join("\n")
      end
    end

    # The Markdown one group gets: a section per test that lists a source, the Must Support section
    # and the group summary.
    class GroupDescription
      def initialize(group, trace)
        @group = group
        @trace = trace
        @fitting = trace.fitting(group)
        @listed = trace.listed(group)
      end

      def to_h
        return {} if @fitting.empty? && @listed.empty?

        test_sections.merge(must_support_section).merge(group: summary)
      end

      private

      def test_sections
        test_ids = [*@group.tests].map { |test| test[:id].to_s }
        @listed.group_by { |placement| placement.test[:id].to_s }.slice(*test_ids).transform_values do |placements|
          Markdown.section(placements.first.intro, Markdown.source_list(placements, @trace))
        end
      end

      def must_support_test = @group.find_test("must_support")

      # What G's own profile checks; only when G has a must_support test.
      def must_support_reads
        must_support_test ? reads.select { |read| @trace.by_group?(@group, read.path) } : []
      end

      def must_support_section
        checked = must_support_reads
        return {} if checked.empty?

        intro = format(Markdown::INTROS["must_support"], resource: @group.resource)
        { must_support_test[:id].to_s => Markdown.section(intro, Markdown.element_list(checked)) }
      end

      def reads = @fitting.flat_map(&:reads)

      def summary
        lines = @fitting.map { |placement| placement.source.form }.uniq.map { |form| summary_line(form) }
        unchecked = reads.reject { |read| @trace.by_source?(read.source, read.path) }
        Markdown.section(format(Markdown::INTROS[:group], resource: @group.profile_name || @group.resource),
                         lines.join("\n"),
                         *Markdown.block(:not_tested, Markdown.source_list(@fitting.reject(&:test), @trace)),
                         *Markdown.block(:not_checked, Markdown.element_list(unchecked)))
      end

      def summary_line(form)
        labels = test_labels(form)
        "- **#{form.title}**: " +
          (labels.empty? ? "no test in this group makes its requests" : "see the #{Markdown.sentence(labels)}")
      end

      def test_labels(form)
        tested = @fitting.select { |placement| placement.test && placement.source.form.equal?(form) }
        must_support = must_support_reads.any? { |read| read.form.equal?(form) }
        [*tested.map(&:test_label), *("Must Support" if must_support)].uniq
      end
    end
  end
end
