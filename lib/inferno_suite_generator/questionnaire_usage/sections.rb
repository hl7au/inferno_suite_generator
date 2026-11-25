# frozen_string_literal: true

require_relative "checked_elements"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Writes the "Used in questionnaires" sections.
    class Sections
      HEADING = "**Used in questionnaires**"
      NOT_CHECKED_MARK = "(not checked)"
      READS = "A form can pre-fill an item only if the server returns the elements the item reads."
      GROUP_READS = "#{READS} Elements marked #{NOT_CHECKED_MARK} are neither Must Support nor required by the " \
                    "profile, so this group's tests do not check them.".freeze
      NOT_TESTED = "No test in this group makes these requests or writes these resources, so nothing checks what " \
                   "these forms get from them."
      NOT_CHECKED = "The profile neither marks these elements Must Support nor requires them, so no test checks " \
                    "that the server returns them."
      UPDATE_INTRO = "These questionnaires in the IG update existing %<resource>s resources from their answers."
      TEST_INTROS = {
        "read" => "These questionnaires in the IG read %<resource>s resources as this test does: by id, or as " \
                  "the resource a form is opened for. #{GROUP_READS}",
        "search" => "These questionnaires in the IG make this search. #{GROUP_READS}",
        "include" => "These questionnaires in the IG fetch %<resource>s resources through this search's " \
                     "_include. #{READS} Elements marked #{NOT_CHECKED_MARK} are neither Must Support nor " \
                     "required by any %<resource>s profile in this suite, so no test checks them.",
        "create" => "These questionnaires in the IG create %<resource>s resources from their answers.",
        "patch" => UPDATE_INTRO,
        "update" => UPDATE_INTRO
      }.freeze
      MAX_ITEM_LINES = 25
      MAX_ITEMS = 10

      # One element path the items of a source read.
      Element = Data.define(:label, :checked)

      def initialize(groups, sources)
        @groups = groups
        @sources = {}
        sources.each { |source| source.groups.each { |group| (@sources[group] ||= []) << source } }
        @checked = Hash.new { |checked, group| checked[group] = CheckedElements.new(group) }
        @shared = {}
        @tests = {}
      end

      def to_h
        traced = @groups.select { |group| @sources.key?(group) }
        sections = traced.to_h { |group| [group, own_sections(group, @sources[group])] }
        requested(traced).each do |test, group, sources|
          (sections[test[:group]] ||= {})[test[:id].to_s] = test_section(test, group, sources)
        end
        sections.transform_values(&:compact)
      end

      private

      def own_sections(group, sources)
        sections = { group: summary(group, sources.select(&:shown?)) }
        test = must_support_test(group, sources)
        sections[test[:id].to_s] = must_support_section(group, sources) if test
        sections
      end

      def requested(traced)
        pairs = traced.flat_map { |group| @sources[group].map { |source| [source, group] } }
        pairs.select { |pair| test(*pair) }.group_by { |pair| test(*pair)[:id] }.values.map do |listed|
          [test(*listed.first), listed.first.last, listed.map(&:first).uniq]
        end
      end

      def test(source, group)
        @tests.fetch([source, group]) do |key|
          lookups = source.shown? ? source.requesting(group, @groups).product(source.lookups(group.resource)) : []
          @tests[key] = lookups.lazy.filter_map { |base, (kind, details)| found_test(base, kind, details) }.first
        end
      end

      def found_test(group, kind, details)
        test = group.find_test(kind, **details)
        return unless test

        label = case kind
                when "search" then "search by #{test[:search_names].join(" + ")}"
                when "include" then "search with _include in #{group.title || group.resource}"
                else kind
                end
        test.merge(group:, label:)
      end

      def must_support_test(group, sources)
        test = group.find_test("must_support")
        test if test && sources.any? { |source| own_elements(source, group).any? }
      end

      def shared_elements(source)
        @shared[source] ||= read_elements(source, source.groups)
      end

      def read_elements(source, groups)
        checked = groups.map { |group| @checked[group] }
        source.item_uses.flat_map(&:reads).uniq.to_h do |path|
          checking = checked.find { |paths| paths.checked?(path) }
          [path, Element.new(label: (checking || checked.first).label(path), checked: !checking.nil?)]
        end
      end

      def own_elements(source, group)
        read_elements(source, [group]).select { |_path, element| element.checked }
      end

      def section(intro, list)
        "#{[HEADING, "", intro, "", list].join("\n")}\n" unless list.empty?
      end

      def test_section(test, group, sources)
        section(format(TEST_INTROS.fetch(test[:kind]), resource: group.resource), source_list(sources, group))
      end

      def must_support_section(group, sources)
        section("Items in these questionnaires read elements of #{group.resource} that this group's tests check. " \
                "#{READS}",
                element_list(sources) { |source| own_elements(source, group) })
      end

      def summary(group, sources)
        return if sources.empty?

        lines = [HEADING, "", summary_intro(group), "", form_list(group, sources)]
        not_tested = source_list(sources.reject { |source| test(source, group) }, group, search_check: true)
        lines.push("", "**Not tested by this group**", "", NOT_TESTED, "", not_tested) unless not_tested.empty?
        not_checked = element_list(sources) { |source| shared_elements(source).reject { |_path, read| read.checked } }
        lines.push("", "**Elements not checked**", "", NOT_CHECKED, "", not_checked) unless not_checked.empty?
        "#{lines.join("\n")}\n"
      end

      def summary_intro(group)
        "These questionnaires in the IG read or create #{group.profile_name || group.resource} resources. The " \
          "tests that make the same requests list the form items that depend on them."
      end

      def form_list(group, sources)
        must_support = group.find_test("must_support")
        forms(sources).map do |title, listed|
          labels = listed.filter_map { |source| test(source, group)&.fetch(:label) }
          labels << "Must Support" if must_support && listed.any? { |source| own_elements(source, group).any? }
          labels.uniq!
          next "- **#{title}**: no test in this group makes its requests" if labels.empty?

          tests = labels.size > 1 ? "#{labels[0...-1].join(", ")} and #{labels.last} tests" : "#{labels.first} test"
          "- **#{title}**: see the #{tests}"
        end.join("\n")
      end

      def forms(sources)
        by_form = sources.select(&:shown?).group_by { |source| source.form.key }.values
        titles = by_form.map { |listed| listed.first.form.label }
        by_form.map do |listed|
          form = listed.first.form
          title = form.label
          [titles.count(title) > 1 && form.version ? "#{title}, version #{form.version}" : title, listed]
        end
      end

      def source_list(sources, group, search_check: false)
        forms(sources).flat_map do |title, listed|
          ["- **#{title}**", *listed.flat_map { |source| source_lines(source, group, search_check) }]
        end.join("\n")
      end

      def source_lines(source, group, search_check)
        query = source.query
        uses = source.item_uses
        details = [query && "Request: #{query}",
                   (search_line(query.search_params, group) if search_check && source.search?),
                   *(uses.empty? ? [source.unused_line] : item_lines(uses, shared_elements(source)))].compact
        ["  - #{source.heading(group.resource)}", *details.map { |line| "    - #{line}" }]
      end

      def search_line(names, group)
        tested = group.searches.to_a.map { |search| search[:names] }
        same = tested.find { |searched| searched.to_set == names.to_set }
        return "This group searches by the same parameters, #{same.join(" + ")}, but has no test for it" if same

        others = "; this group tests #{tested.map { |searched| searched.join(" + ") }.join(", ")}" if tested.any?
        "A search by #{names.join(" + ")}#{others}"
      end

      def item_lines(uses, elements)
        items = uses.group_by(&:link_id).values
        more = items.size - MAX_ITEM_LINES
        [*items.first(MAX_ITEM_LINES).map { |item| item_line(item, elements) },
         ("and #{more} more items" if more.positive?)].compact
      end

      def item_line(uses, elements)
        reads = uses.flat_map(&:reads).uniq.map do |path|
          element = elements.fetch(path)
          element.checked ? element.label : "#{element.label} #{NOT_CHECKED_MARK}"
        end
        details = [uses.filter_map(&:action).uniq.join(", "), ("reads #{reads.join(", ")}" if reads.any?)]
        details = details.compact.reject(&:empty?).join("; ")
        "**#{uses.first.label}**#{": #{details}" unless details.empty?}"
      end

      def element_list(sources)
        forms(sources).flat_map do |title, listed|
          items = listed.each_with_object({}) do |source, by_label|
            listing = yield source
            source.item_uses.each do |use|
              listing.values_at(*use.reads).compact.each { |element| (by_label[element.label] ||= []) << use.label }
            end
          end
          next [] if items.empty?

          ["- **#{title}**", *items.map { |label, labels| "  - **#{label}**: #{items_text(labels.uniq)}" }]
        end.join("\n")
      end

      def items_text(items)
        more = items.size - MAX_ITEMS
        [items.first(MAX_ITEMS).join(", "), ("and #{more} more" if more.positive?)].compact.join(", ")
      end
    end
  end
end
