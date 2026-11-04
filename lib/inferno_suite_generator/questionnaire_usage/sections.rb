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
      private_constant :HEADING, :NOT_CHECKED_MARK, :READS

      def initialize(delivery)
        @delivery = delivery
      end

      def write(descriptions)
        @delivery.each_group do |group, placements|
          write_must_support(descriptions, group, placements)
          descriptions.group(group, GroupSummary.new(group, placements).markdown)
        end
        @delivery.test_listings.each do |listing|
          destination = listing.destination
          descriptions.test(destination.group, destination.test_id, TestSection.new(listing).markdown)
        end
      end

      private

      def write_must_support(descriptions, group, placements)
        test = placements.filter_map(&:must_support).first
        descriptions.test(group, test.test_id, MustSupportSection.new(group, placements).markdown) if test
      end

      # The shown placements grouped by the questionnaire they come from, in the
      # order first seen, each with the title a section shows for it.
      class Forms
        include Enumerable

        def initialize(placements)
          @forms = placements.select(&:shown?).group_by { |placement| placement.entry.form_key }
        end

        # Yields each form's title and placements.
        def each
          @forms.each_value { |placements| yield title(placements.first.entry), placements }
        end

        private

        # The title, or the URL or id for an untitled form, with the version when
        # another form here has the same title, as an assembled modular form does.
        def title(entry)
          title = entry.form_title
          version = entry.form_version
          same_title = @forms.values.count { |placements| placements.first.entry.form_title == title }
          same_title > 1 && version ? "#{title}, version #{version}" : title
        end
      end

      # A section with an intro and a list, or no section when the list is empty.
      # Classes that include it give `intro` and `list`.
      module ListSection
        def markdown
          "#{[HEADING, "", intro, "", list].join("\n")}\n" unless list.empty?
        end
      end

      # The section of one test that makes a request.
      class TestSection
        include ListSection

        GROUP_READS = "#{READS} Elements marked #{NOT_CHECKED_MARK} are neither Must Support nor required by the " \
                      "profile, so this group's tests do not check them.".freeze

        def initialize(listing)
          @listing = listing
          @group = listing.groups.first
        end

        private

        def list
          @list ||= SourceList.new(@listing.placements, @group).markdown
        end

        def intro
          resource = @group.resource
          case @listing.destination.kind
          when "read"
            "These questionnaires in the IG read #{resource} resources as this test does: by id, or as the " \
            "resource a form is opened for. #{GROUP_READS}"
          when "search" then "These questionnaires in the IG make this search. #{GROUP_READS}"
          when "include" then include_intro(resource)
          when "create" then "These questionnaires in the IG create #{resource} resources from their answers."
          else "These questionnaires in the IG update existing #{resource} resources from their answers."
          end
        end

        # An include test belongs to another group than the entries it lists, and
        # those can be traced for several profiles.
        # :reek:UtilityFunction
        def include_intro(resource)
          "These questionnaires in the IG fetch #{resource} resources through this search's _include. #{READS} " \
            "Elements marked #{NOT_CHECKED_MARK} are neither Must Support nor required by any #{resource} " \
            "profile in this suite, so no test checks them."
        end
      end

      # The section of a group's Must Support test.
      class MustSupportSection
        include ListSection

        def initialize(group, placements)
          @group = group
          @placements = placements
        end

        private

        def list
          @list ||= ElementList.new(@placements).must_support
        end

        def intro
          "Items in these questionnaires read Must Support elements of #{@group.resource}. A form can pre-fill " \
            "an item only if the server returns the elements it reads."
        end
      end

      # The section at the end of a group's description. The details are in the
      # descriptions of the tests that make each request, so the group lists what
      # is left:
      #
      # - each questionnaire, with the tests that list its items
      # - **Not tested by this group**: the sources no test makes the request of
      # - **Elements not checked**: the elements items read that no test checks
      class GroupSummary
        NOT_TESTED = "No test in this group makes these requests or writes these resources, so nothing checks what " \
                     "these forms get from them."
        NOT_CHECKED = "The profile neither marks these elements Must Support nor requires them, so no test checks " \
                      "that the server returns them."

        def initialize(group, placements)
          @group = group
          @placements = placements.select(&:shown?)
        end

        def markdown
          return if @placements.empty?

          lines = [HEADING, "", intro, "", forms_list]
          not_tested = SourceList.new(@placements.reject(&:request), @group, search_check: true).markdown
          lines.push("", "**Not tested by this group**", "", NOT_TESTED, "", not_tested) unless not_tested.empty?
          not_checked = ElementList.new(@placements).not_checked
          lines.push("", "**Elements not checked**", "", NOT_CHECKED, "", not_checked) unless not_checked.empty?
          "#{lines.join("\n")}\n"
        end

        private

        def intro
          "These questionnaires in the IG read or create #{@group.profile_name || @group.resource} resources. The " \
            "tests that make the same requests list the form items that depend on them."
        end

        def forms_list
          Forms.new(@placements).map do |title, placements|
            labels = test_labels(placements)
            next "- **#{title}**: no test in this group makes its requests" if labels.empty?

            "- **#{title}**: see the #{sentence(labels)} #{labels.size == 1 ? "test" : "tests"}"
          end.join("\n")
        end

        # The tests that make a request first, then the Must Support test.
        # :reek:UtilityFunction
        def test_labels(placements)
          tests = placements.filter_map(&:request) + placements.filter_map(&:must_support)
          tests.map(&:label).uniq
        end

        # :reek:UtilityFunction
        def sentence(labels)
          labels.size > 1 ? "#{labels[0...-1].join(", ")} and #{labels.last}" : labels.first
        end
      end

      # The nested list of the sources of some placements, by questionnaire, and
      # the items that use each. Only `TraceEntry#shown?` entries are listed, each
      # with its `item_uses`. "" when there are none.
      class SourceList
        # search_check: whether a query says how the group's search tests
        # compare to it, which only the group summary needs.
        def initialize(placements, group, search_check: false)
          @group = group
          @search_check = search_check
          @forms = Forms.new(placements)
        end

        def markdown
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

        # uses: a `TraceEntry#item_uses`.
        # reads: the entry's `Delivery::Placement#reads`.
        def initialize(uses, reads)
          @items = uses.group_by(&:link_id).values
          @reads = reads
        end

        # Up to `MAX` lines, then one that counts the rest.
        def lines
          more = @items.size - MAX
          [*@items.first(MAX).map { |uses| line(uses) },
           ("and #{more} more items, listed in questionnaire_usage.yml" if more.positive?)].compact
        end

        private

        # Leaves out a part the item has nothing for.
        def line(uses)
          details = [actions(uses), reads(uses)].compact.join("; ")
          "**#{uses.first.label}**#{": #{details}" unless details.empty?}"
        end

        def actions(uses)
          actions = uses.filter_map(&:action).uniq
          actions.join(", ") unless actions.empty?
        end

        def reads(uses)
          paths = uses.flat_map(&:reads).uniq
          "reads #{paths.map { |path| read_label(path) }.join(", ")}" unless paths.empty?
        end

        def read_label(path)
          read = @reads.fetch(path)
          read.checked ? read.label : "#{read.label} #{NOT_CHECKED_MARK}"
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

      # The element paths the form items of one group's placements read, each
      # with the items that read it, by questionnaire. The Must Support test lists
      # the ones the group checks, and the group summary the ones no test checks:
      #
      #   - **GP Chronic Condition Management Plan**
      #     - **birthDate**: Date of birth, Age
      #
      # Elements come in the order the form first reads them.
      class ElementList
        MAX_ITEMS = 10

        def initialize(placements)
          @forms = Forms.new(placements)
        end

        # The elements the group's Must Support test lists; "" when there are none.
        def must_support
          list(&:must_support_reads)
        end

        # The elements no test checks; "" when there are none.
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
            placement.entry.item_uses.each { |use| add_item(by_label, use, listed) }
          end
        end

        # :reek:UtilityFunction
        def add_item(by_label, use, listed)
          item = use.label
          listed.values_at(*use.reads).compact.each do |read|
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

      private_constant :Forms, :ListSection, :TestSection, :MustSupportSection, :GroupSummary, :SourceList, :ItemLines,
                       :SearchCheck, :ElementList
    end
  end
end
