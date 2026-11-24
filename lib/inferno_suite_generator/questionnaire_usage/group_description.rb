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
        "search" => "These questionnaires in the IG make this search. #{reads} #{not_checked}",
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

      # untested: the sources no test of the group lists, which also compare to the group's searches.
      def self.source_list(placements, trace, untested: false)
        by_form(placements) { |placement| source_lines(placement, trace, untested) }
      end

      def self.source_lines(placement, trace, untested)
        source = placement.source
        uses = source.uses
        rest = uses.size - ITEM_CAP
        lines = [*placement.details(untested), *uses.first(ITEM_CAP).map { |use| item_line(source, use, trace) },
                 *("and #{rest} more items" if rest.positive?)]
        ["  - #{source.heading}", *lines.map { |line| "    - #{line}" }]
      end

      def self.item_line(source, use, trace)
        reads = use.paths.map do |path|
          label = trace.label(source, path)
          trace.by_source?(source, path) ? label : "#{label} (not checked)"
        end
        "**#{use.label}**: #{use.actions.join(", ")}#{"; reads #{reads.join(", ")}" unless reads.empty?}"
      end

      # One line per element and form, with the labels of the items that read it.
      def self.element_list(reads, trace)
        rows = reads.group_by { |read| [read.form, read.path] }.values.map { |same| element_row(same) }
        by_form(rows) { |row| "  - **#{trace.label(row.source, row.path)}**: #{row.label}" }
      end

      def self.element_row(same)
        source, path = same.first.to_a
        Read.new(source, path, capped(same.map(&:label).uniq))
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
        { must_support_test[:id].to_s => Markdown.section(intro, Markdown.element_list(checked, @trace)) }
      end

      def reads = @fitting.flat_map(&:reads)

      def summary
        intro = format(Markdown::INTROS[:group], resource: @group.profile_name || @group.resource)
        Markdown.section(intro, summary_lines, *not_tested, *not_checked)
      end

      def summary_lines
        @fitting.map { |placement| placement.source.form }.uniq.map { |form| summary_line(form) }.join("\n")
      end

      def not_tested
        Markdown.block(:not_tested, Markdown.source_list(@fitting.reject(&:test), @trace, untested: true))
      end

      def not_checked
        Markdown.block(:not_checked, Markdown.element_list(reads.reject { |read| read.checked_in?(@trace) }, @trace))
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
