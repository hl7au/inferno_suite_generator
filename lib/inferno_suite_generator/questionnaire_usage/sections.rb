# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Writes the "Used in questionnaires" sections a Delivery decided on to the
    # descriptions:
    #
    # - a test section for each test that makes a request: the questionnaires,
    #   the sources in each whose request it makes, and the items that use them
    # - a Must Support section for a group's Must Support test: the elements it
    #   checks that form items read
    # - a group summary for each group: the questionnaires with the tests that
    #   list them, the sources no test makes the request of, and the elements no
    #   test checks
    #
    # Sections use only bold and plain text, since Inferno shows tables without
    # borders and raw HTML as text.
    class Sections
      HEADING = "## Used in questionnaires"
      NOT_CHECKED_MARK = "(not checked)"
      READS = "A form can pre-fill an item only if the server returns the elements the item reads."
      GROUP_READS = "#{READS} Elements marked #{NOT_CHECKED_MARK} are neither Must Support nor required by the " \
                    "profile, so this group's tests do not check them.".freeze
      NOT_TESTED = "No test in this group makes these requests or writes these resources, so nothing checks what " \
                   "these forms get from them."
      NOT_CHECKED = "The profile neither marks these elements Must Support nor requires them, so no test checks " \
                    "that the server returns them."
      # The intro of a test section, by the kind of test. An include test
      # belongs to another group than the entries it lists, and those can be
      # traced for several profiles. A patch test reads as an update.
      TEST_INTROS = {
        "read" => "These questionnaires in the IG read %<resource>s resources as this test does: by id, or as the " \
                  "resource a form is opened for. #{GROUP_READS}",
        "search" => "These questionnaires in the IG make this search. #{GROUP_READS}",
        "include" => "These questionnaires in the IG fetch %<resource>s resources through this search's _include. " \
                     "#{READS} Elements marked #{NOT_CHECKED_MARK} are neither Must Support nor required by any " \
                     "%<resource>s profile in this suite, so no test checks them.",
        "create" => "These questionnaires in the IG create %<resource>s resources from their answers.",
        "update" => "These questionnaires in the IG update existing %<resource>s resources from their answers."
      }.freeze

      def initialize(delivery)
        @delivery = delivery
      end

      def write(descriptions)
        @delivery.each_group { |group, placements| write_group(descriptions, group, placements) }
        @delivery.test_listings.each do |listing|
          destination = listing.destination
          descriptions.test(destination.group, destination.test_id, test_section(listing))
        end
      end

      private

      def write_group(descriptions, group, placements)
        test = placements.filter_map(&:must_support).first
        descriptions.test(group, test.test_id, must_support_section(group, placements)) if test
        descriptions.group(group, group_summary(group, placements.select(&:shown?)))
      end

      # A section with an intro and a list, or `nil` when the list is empty.
      def section(intro, list)
        "#{[HEADING, "", intro, "", list].join("\n")}\n" unless list.empty?
      end

      # The section of one test that makes a request.
      def test_section(listing)
        group = listing.groups.first
        intro = TEST_INTROS.fetch(listing.destination.kind) { TEST_INTROS["update"] }
        section(format(intro, resource: group.resource), Lists.sources(listing.placements, group))
      end

      def must_support_section(group, placements)
        section("Items in these questionnaires read Must Support elements of #{group.resource}. A form can " \
                "pre-fill an item only if the server returns the elements it reads.",
                Lists.elements(placements, &:must_support_reads))
      end

      # The section at the end of a group's description, for its shown
      # placements. The details are in the descriptions of the tests that make
      # each request, so the group lists what is left: each questionnaire with
      # the tests that list its items, the sources no test makes the request
      # of, and the elements items read that no test checks.
      def group_summary(group, placements)
        return if placements.empty?

        lines = [HEADING, "", summary_intro(group), "", forms_list(placements)]
        not_tested = Lists.sources(placements.reject(&:request), group, search_check: true)
        lines.push("", "**Not tested by this group**", "", NOT_TESTED, "", not_tested) unless not_tested.empty?
        not_checked = Lists.elements(placements) { |placement| placement.reads.reject { |_path, read| read.checked } }
        lines.push("", "**Elements not checked**", "", NOT_CHECKED, "", not_checked) unless not_checked.empty?
        "#{lines.join("\n")}\n"
      end

      def summary_intro(group)
        "These questionnaires in the IG read or create #{group.profile_name || group.resource} resources. The " \
          "tests that make the same requests list the form items that depend on them."
      end

      # Each questionnaire with the tests that list it: those that make a
      # request first, then the Must Support test.
      def forms_list(placements)
        Lists.forms(placements).map do |title, listed|
          labels = (listed.filter_map(&:request) + listed.filter_map(&:must_support)).map(&:label).uniq
          next "- **#{title}**: no test in this group makes its requests" if labels.empty?

          "- **#{title}**: see the #{sentence(labels)} #{labels.size == 1 ? "test" : "tests"}"
        end.join("\n")
      end

      def sentence(labels)
        labels.size > 1 ? "#{labels[0...-1].join(", ")} and #{labels.last}" : labels.first
      end

      # The nested Markdown lists the sections share. Each takes placements and
      # lists only the shown ones, by questionnaire. "" when there are none.
      module Lists
        MAX_ITEM_LINES = 25
        MAX_ITEMS = 10

        module_function

        # `[title, placements]` per questionnaire, in the order first seen. The
        # title is the form's, with the version when another form here has the
        # same title, as an assembled modular form does.
        def forms(placements)
          by_form = placements.select(&:shown?).group_by { |placement| placement.entry.form_key }.values
          titles = by_form.map { |listed| listed.first.entry.form_title }
          by_form.map { |listed| [form_title(listed.first.entry, titles), listed] }
        end

        def form_title(entry, titles)
          title = entry.form_title
          version = entry.form_version
          titles.count(title) > 1 && version ? "#{title}, version #{version}" : title
        end

        # The sources and the items that use each. search_check: whether a query
        # says how the group's search tests compare to it, which only the group
        # summary needs.
        def sources(placements, group, search_check: false)
          forms(placements).flat_map do |title, listed|
            ["- **#{title}**", *listed.flat_map { |placement| source_lines(placement, group, search_check) }]
          end.join("\n")
        end

        def source_lines(placement, group, search_check)
          entry = placement.entry
          query = entry.query
          params = entry.search_params if search_check
          uses = entry.item_uses
          details = [query && "Request: #{query}", (search_line(params, group) if params),
                     *(uses.empty? ? [entry.unused_line] : item_lines(uses, placement.reads))].compact
          ["  - #{entry.heading(group.resource)}", *details.map { |line| "    - #{line}" }]
        end

        # How the group's searches compare to a query none of its search tests
        # makes, or `nil` when the query selects by no parameter.
        def search_line(names, group)
          return if names.empty?

          tested = group.searches.to_a.map { |search| search[:names] }
          same = tested.find { |searched| searched.to_set == names.to_set }
          return "This group searches by the same parameters, #{same.join(" + ")}, but has no test for it" if same

          others = "; this group tests #{tested.map { |searched| searched.join(" + ") }.join(", ")}" if tested.any?
          "A search by #{names.join(" + ")}#{others}"
        end

        # One line per item, in document order, like
        # `**Height**: pre-fills the answer, shows or hides the item; reads value.value`,
        # up to `MAX_ITEM_LINES`, then one that counts the rest.
        def item_lines(uses, reads)
          items = uses.group_by(&:link_id).values
          more = items.size - MAX_ITEM_LINES
          [*items.first(MAX_ITEM_LINES).map { |item| item_line(item, reads) },
           ("and #{more} more items, listed in questionnaire_usage.yml" if more.positive?)].compact
        end

        # reads: the entry's `Delivery::Placement#reads`.
        def item_line(uses, reads)
          details = [uses.filter_map(&:action).uniq.join(", "), reads_text(uses, reads)].reject(&:empty?).join("; ")
          "**#{uses.first.label}**#{": #{details}" unless details.empty?}"
        end

        def reads_text(uses, reads)
          labels = uses.flat_map(&:reads).uniq.map do |path|
            read = reads.fetch(path)
            read.checked ? read.label : "#{read.label} #{NOT_CHECKED_MARK}"
          end
          labels.empty? ? "" : "reads #{labels.join(", ")}"
        end

        # The element paths the items read, each with the items that read it, in
        # the order the form first reads them:
        #
        #   - **GP Chronic Condition Management Plan**
        #     - **birthDate**: Date of birth, Age
        #
        # The block gives the `{ path => ElementRead }` to list for a placement.
        def elements(placements, &reads)
          forms(placements).flat_map do |title, listed|
            by_label = items_by_element(listed, reads)
            next [] if by_label.empty?

            ["- **#{title}**", *by_label.map { |label, items| "  - **#{label}**: #{items_text(items)}" }]
          end.join("\n")
        end

        # `{ element label => item labels }`
        def items_by_element(placements, reads)
          placements.each_with_object({}) do |placement, by_label|
            listed = reads.call(placement)
            placement.entry.item_uses.each do |use|
              listed.values_at(*use.reads).compact.each do |read|
                by_label[read.label] = by_label.fetch(read.label, []) | [use.label]
              end
            end
          end
        end

        # Up to `MAX_ITEMS` labels, then a count of the rest.
        def items_text(items)
          more = items.size - MAX_ITEMS
          [items.first(MAX_ITEMS).join(", "), ("and #{more} more" if more.positive?)].compact.join(", ")
        end
      end
      private_constant :Lists
    end
  end
end
