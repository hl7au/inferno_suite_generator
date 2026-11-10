# frozen_string_literal: true

require_relative "../core/test_index"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Writes the "Used in questionnaires" sections to the descriptions, as its
    # Delivery decides:
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

      # traces: `{ profile_url => [TraceEntry] }`, from `Tracer#trace`.
      def initialize(groups, traces)
        @delivery = Delivery.new(groups, traces)
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

      # Decides which tests list each trace entry and which elements its items
      # read count as checked, once and before anything is rendered, so the test
      # sections and the group summaries can't disagree.
      class Delivery
        # A test that lists an entry. `label` names the test in the group summary.
        Destination = Data.define(:group, :test_id, :kind, :label)

        # One element path a trace entry's items read: how sections name it, and
        # whether it counts as checked.
        ElementRead = Data.define(:path, :label, :checked)

        # One trace entry of one group. `request` is the Destination of the test
        # that makes its request, and `must_support` the group's Must Support
        # test when its items read an element the group checks. Each is `nil`
        # when no test lists the entry for that reason.
        #
        # `reads` and `must_support_reads` are `{ path => ElementRead }`. `reads`
        # has every path the entry's items read, and is the same for each group
        # the entry was traced for: an element is checked when any of them checks
        # it. `must_support_reads` has the paths this group checks, as it names
        # them, since its Must Support test can list only those.
        Placement = Data.define(:group, :entry, :request, :must_support, :reads, :must_support_reads) do
          def shown?
            entry.shown?
          end
        end

        # A test that makes the request of these placements, one per entry, and
        # the groups they were traced for. Only an `_include` test has several
        # groups: its entries link to every group of the target type.
        TestListing = Data.define(:destination, :placements, :groups)

        # traces: `{ profile_url => [trace entries] }`, from `Tracer#trace`.
        def initialize(groups, traces)
          @groups = groups
          reads = shared_reads(groups, traces)
          @placements = groups.filter_map do |group|
            entries = traces[group.profile_url]
            [group, placements(group, entries, reads)] if entries
          end
        end

        # Yields each traced group and its Placements, in trace order.
        def each_group(&)
          @placements.each(&)
        end

        # A TestListing per test that makes a request, listing a shared entry once.
        def test_listings
          requested = @placements.flat_map(&:last).select(&:request)
          requested.group_by { |placement| placement.request.test_id }.values.map do |listed|
            TestListing.new(destination: listed.first.request, placements: listed.uniq(&:entry),
                            groups: listed.map(&:group).uniq)
          end
        end

        private

        def placements(group, entries, reads)
          checked_elements = CheckedElements.new([group])
          must_support = find(group, "must_support")
          entries.map do |entry|
            own = element_reads(entry, checked_elements).select { |_path, read| read.checked }
            request = request_test(group, entry) if entry.shown?
            Placement.new(group:, entry:, request:, must_support: (must_support if own.any?), reads: reads[entry],
                          must_support_reads: own)
          end
        end

        # The first test the entry's lookups find, in the group it was traced for
        # or, for an `_include`, in the groups of the searched type.
        def request_test(group, entry)
          type = entry.request_type
          bases = type ? @groups.select { |base| base.resource == type } : [group]
          bases.product(entry.request_lookups(group.resource)).lazy
               .filter_map { |base, (kind, details)| find(base, kind, **details) }.first
        end

        # The Destination of the group's first test of this kind, or `nil`.
        # :reek:UtilityFunction
        def find(group, kind, **details)
          test = Generator::TestIndex.new(group).find(kind, **details)
          Destination.new(group, test.id, test.kind, label(group, test)) if test
        end

        # :reek:UtilityFunction
        def label(group, test)
          case test.kind
          when "search" then "search by #{test.details[:search_names].join(" + ")}"
          when "include" then "search with _include in #{group.title || group.resource}"
          when "must_support" then "Must Support"
          else test.kind
          end
        end

        # `{ entry => { path => ElementRead } }`, answered for all the groups each
        # entry was traced for.
        def shared_reads(groups, traces)
          groups_by_entry = groups.each_with_object({}) do |group, found|
            traces[group.profile_url].to_a.each { |entry| (found[entry] ||= []) << group }
          end
          groups_by_entry.to_h { |entry, traced| [entry, element_reads(entry, CheckedElements.new(traced))] }
        end

        # :reek:UtilityFunction
        def element_reads(entry, checked_elements)
          paths = entry.item_uses.flat_map(&:reads).uniq
          paths.to_h do |path|
            [path, ElementRead.new(path:, label: checked_elements.label(path),
                                   checked: checked_elements.checked?(path))]
          end
        end
      end

      # The element paths the tests of one or more groups check: the ones their
      # profiles mark Must Support or require, `id`, and the value of a Must
      # Support extension.
      #
      # A path counts as checked when any of the groups checks it, and is labeled
      # as the group that checks it names it, so a slice one profile defines keeps
      # its name. A test can make the request of entries traced for several groups
      # of one type.
      class CheckedElements
        def initialize(groups)
          @profiles = groups.map { |group| Profile.new(group) }
        end

        def checked?(path)
          @profiles.any? { |profile| profile.checked?(path) }
        end

        # The path as sections show it: an extension the profile slices as Must
        # Support is named by its slice, like `extension:sliceName`, and any other
        # by the last part of its URL, like `extension[individual-pronouns]`.
        def label(path)
          (@profiles.find { |profile| profile.checked?(path) } || @profiles.first).label(path)
        end

        # The rule for one group's profile.
        #
        # Trace paths name an extension as `extension[url=U]`. The Must Support test
        # looks only for the URL of an extension the profile slices, so inside one
        # only what the validation test holds it to counts as checked: its value,
        # or the `value` part of a complex extension. Other parts, like `period`,
        # are optional, and what a value holds isn't known here, since the
        # extension's definition may not be loaded.
        #
        # A trace path names a choice element by its type, like `valueQuantity`,
        # where the profile has `value[x]`, so it is compared as `value`.
        class Profile
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
        private_constant :Profile
      end

      private_constant :Lists, :Delivery, :CheckedElements
    end
  end
end
