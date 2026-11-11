# frozen_string_literal: true

require_relative "../core/test_index"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Writes the "Used in questionnaires" sections: one per test that makes a request, one for the Must Support
    # test and a group summary. Only bold and plain text: Inferno shows tables without borders and HTML as text.
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
      # By the listing test's kind. An include test lists entries of other groups, which can be of several
      # profiles, so its intro names none.
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

      def initialize(groups, trace)
        @delivery = Delivery.new(groups, trace)
      end

      def write(descriptions)
        @delivery.each_group { |group, placements| write_group(descriptions, group, placements) }
        @delivery.request_listings.each do |listing|
          test = listing.test
          descriptions.test(test.group, test.test_id, test_section(listing))
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

      def test_section(listing)
        group = listing.groups.first
        intro = format(TEST_INTROS.fetch(listing.test.kind), resource: group.resource)
        section(intro, Lists.sources(listing.placements, group))
      end

      def must_support_section(group, placements)
        section("Items in these questionnaires read elements of #{group.resource} that this group's tests check. " \
                "#{READS}",
                Lists.elements(placements, &:must_support_reads))
      end

      # The summary at the end of a group's description. The tests that make each request list the details, so
      # it lists what is left: each form with its tests, the sources no test requests, and unchecked elements.
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

      # Each questionnaire with its tests: those that make a request first, then the Must Support test.
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

        # `[title, placements]` per questionnaire, in the order first seen. The title gets the version when
        # another form has the same title, as an assembled modular form does.
        def forms(placements)
          by_form = placements.select(&:shown?).group_by { |placement| placement.entry.header.key }.values
          forms = by_form.map { |listed| listed.first.entry.header }
          titles = forms.map(&:label)
          forms.zip(by_form).map { |form, listed| [form_title(form, titles), listed] }
        end

        def form_title(form, titles)
          title = form.label
          version = form.version
          titles.count(title) > 1 && version ? "#{title}, version #{version}" : title
        end

        # The sources and the items that use each; `search_check:` adds how the group's searches compare to a query.
        def sources(placements, group, search_check: false)
          forms(placements).flat_map do |title, listed|
            ["- **#{title}**", *listed.flat_map { |placement| source_lines(placement, group, search_check) }]
          end.join("\n")
        end

        def source_lines(placement, group, search_check)
          entry = placement.entry
          query = entry.query
          uses = entry.item_uses
          searched = search_check && entry.request == :search
          details = [query && "Request: #{query}", (search_line(query.search_params, group) if searched),
                     *(uses.empty? ? [entry.unused_line] : item_lines(uses, placement.reads))].compact
          ["  - #{entry.heading(group.resource)}", *details.map { |line| "    - #{line}" }]
        end

        # How the group's searches compare to a query none of its search tests makes.
        def search_line(names, group)
          tested = group.searches.to_a.map { |search| search[:names] }
          same = tested.find { |searched| searched.to_set == names.to_set }
          return "This group searches by the same parameters, #{same.join(" + ")}, but has no test for it" if same

          others = "; this group tests #{tested.map { |searched| searched.join(" + ") }.join(", ")}" if tested.any?
          "A search by #{names.join(" + ")}#{others}"
        end

        # One line per item, like `**Height**: pre-fills the answer; reads value.value`, up to `MAX_ITEM_LINES`,
        # then one that counts the rest.
        def item_lines(uses, reads)
          items = uses.group_by(&:link_id).values
          more = items.size - MAX_ITEM_LINES
          [*items.first(MAX_ITEM_LINES).map { |item| item_line(item, reads) },
           ("and #{more} more items" if more.positive?)].compact
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

        # The paths the items read, each with the items that read it, like `- **birthDate**: Date of birth, Age`.
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
                by_label[read.label] = by_label.fetch(read.label) { [] } | [use.label]
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

      # Decides which tests list each trace entry and which elements count as checked, once, before rendering,
      # so the test sections and group summaries can't disagree.
      class Delivery
        # A listing test. `kind` is its generator test kind, and `label` names the test in the group summary.
        ListingTest = Data.define(:group, :test_id, :kind, :label)

        # One path an entry's items read: its label in sections, and whether it counts as checked.
        ElementRead = Data.define(:path, :label, :checked)

        # One trace entry of one group. `request` and `must_support` are the ListingTests that list it, or `nil`.
        # `reads` has every path its items read, the same for each group traced for it (checked if any checks it);
        # `must_support_reads` only the paths this group checks, named as it names them.
        Placement = Data.define(:group, :entry, :request, :must_support, :reads, :must_support_reads) do
          def shown?
            entry.shown?
          end
        end

        # A request test and its placements, one per entry, with their groups. Only an `_include` test has several
        # groups: its entries link to every group of the target type.
        RequestListing = Data.define(:test, :placements, :groups)

        def initialize(groups, trace)
          @listing_tests = ListingTests.new(groups)
          @trace = trace
          @checked = Hash.new { |checked, group| checked[group] = CheckedElements.new(group) }.compare_by_identity
          @placements = groups.filter_map do |group|
            entries = trace.entries(group)
            [group, placements(group, entries)] unless entries.empty?
          end
        end

        # Yields each traced group and its Placements, in trace order.
        def each_group(&)
          @placements.each(&)
        end

        # A RequestListing per test that makes a request, listing a shared entry once.
        def request_listings
          requested = @placements.flat_map(&:last).select(&:request)
          requested.group_by { |placement| placement.request.test_id }.values.map do |listed|
            RequestListing.new(test: listed.first.request, placements: listed.uniq(&:entry),
                               groups: listed.map(&:group).uniq)
          end
        end

        private

        def placements(group, entries)
          must_support = @listing_tests.must_support(group)
          entries.map do |entry|
            own = element_reads(entry, [group]).select { |_path, read| read.checked }
            request = @listing_tests.request(entry, group) if entry.shown?
            Placement.new(group:, entry:, request:, must_support: (must_support if own.any?),
                          reads: shared_reads(entry), must_support_reads: own)
          end
        end

        # `{ path => ElementRead }`, answered for all the groups that share the entry.
        def shared_reads(entry)
          (@shared_reads ||= {})[entry] ||= element_reads(entry, @trace.groups(entry))
        end

        # A path is checked when any of the groups checks it, and labeled as that group names it, so a slice one
        # profile defines keeps its name.
        def element_reads(entry, groups)
          checked = groups.map { |group| @checked[group] }
          entry.item_uses.flat_map(&:reads).uniq.to_h do |path|
            checking = checked.find { |elements| elements.checked?(path) }
            [path, ElementRead.new(path:, label: (checking || checked.first).label(path), checked: !checking.nil?)]
          end
        end
      end

      # Finds the listing tests: an entry's request test and a group's Must Support test, by the generator's test
      # kinds, which `Generator::TestIndex` finds tests by.
      class ListingTests
        # `[kind, details]` lookups for `TestIndex#find` by request, tried in order, from the entry and its group's
        # type. An `_include` prefers the include test that searches by the same parameters; a FHIRPath Patch goes
        # to the patch test, then the update test, not the one that creates a new resource through update.
        LOOKUPS = {
          read: ->(_entry, _resource) { [["read", {}]] },
          search: ->(entry, _resource) { [["search", { search_names: entry.query.search_params }]] },
          include: lambda do |entry, resource|
            [["include", { search_names: entry.query.search_params, include_targets: [resource] }],
             ["include", { include_targets: [resource] }]]
          end,
          create: ->(_entry, _resource) { [["create", {}]] },
          patch: ->(_entry, _resource) { [["patch", {}], ["update", { option: "update" }]] }
        }.freeze

        def initialize(groups)
          @groups = groups
        end

        # The first test that makes the entry's request, in the group it was traced for or, for an `_include`,
        # in the groups of the searched type. `nil` when the entry makes no request or no test makes it.
        def request(entry, group)
          request = entry.request
          return unless request

          type = entry.query.resource_type if request == :include
          bases = type ? @groups.select { |base| base.resource == type } : [group]
          bases.product(LOOKUPS.fetch(request).call(entry, group.resource)).lazy
               .filter_map { |base, (kind, details)| find(base, kind, **details) }.first
        end

        def must_support(group)
          find(group, "must_support")
        end

        private

        def find(group, kind, **details)
          test = Generator::TestIndex.new(group).find(kind, **details)
          return unless test

          Delivery::ListingTest.new(group:, test_id: test.id, kind: test.kind, label: label(group, test))
        end

        def label(group, test)
          case test.kind
          when "search" then "search by #{test.details[:search_names].join(" + ")}"
          when "include" then "search with _include in #{group.title || group.resource}"
          when "must_support" then "Must Support"
          else test.kind
          end
        end
      end

      # The element paths a group's tests check: Must Support or required by the profile, `id`, and a Must Support
      # extension's value or `value` part, which is all validation enforces inside one: the Must Support test only
      # looks for its URL. A choice element read by its type, like `valueQuantity`, is compared as the element.
      class CheckedElements
        ALWAYS_PRESENT = %w[id].freeze
        EXTENSION_URL = /\A((?:modifierE|e)xtension)\[url=(.+)\]\z/
        EXTENSION_SLICE = /\A(?:modifierE|e)xtension:/
        # After the slice: nothing, the value, or the `value` part and its value.
        EXTENSION_REQUIRED = /\A(?:extension\[url=value\](?:\.value(?:[A-Z]\w*)?)?|value(?:[A-Z]\w*)?)?\z/

        def initialize(group)
          must_supports = group.must_supports || {}
          paths = element_paths(must_supports, group.mandatory_elements.to_a)
          @paths = paths.to_set { |path| plain(path) }
          @choices = choice_paths(paths)
          @slices = must_supports[:extensions].to_a.to_h { |extension| slice(extension) }
        end

        # The path as sections show it: a Must Support extension by its slice, like `extension:sliceName`, and any
        # other extension by the end of its URL, like `extension[individual-pronouns]`.
        def label(path)
          sliced(path).gsub(%r{\[url=(?:[^\]]*/)?([^\]/]+)\]}, '[\1]')
        end

        def checked?(path)
          name = sliced(path)
          ALWAYS_PRESENT.include?(name) || @paths.include?(without_choice_types(name)) || required_by_extension?(name)
        end

        private

        def required_by_extension?(name)
          steps = segments(name)
          slice = steps.rindex { |segment| segment.match?(EXTENSION_SLICE) }
          slice && steps.drop(slice + 1).join(".").match?(EXTENSION_REQUIRED)
        end

        # The path with each extension the profile slices named by its slice.
        def sliced(path)
          segments(path).each_with_object([]) do |segment, done|
            _, member, url = segment.match(EXTENSION_URL).to_a
            done << (@slices[[done.join("."), member, url]] || segment)
          end.join(".")
        end

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

        # The name with each segment that names a choice element by its type,
        # like `valueQuantity` or `effectiveDateTime`, written as the element.
        def without_choice_types(name)
          segments(name).each_with_object([]) do |segment, done|
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

      private_constant :Lists, :Delivery, :ListingTests, :CheckedElements
    end
  end
end
