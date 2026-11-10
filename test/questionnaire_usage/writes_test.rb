# frozen_string_literal: true

require_relative "support"

# What tracing writes, through `QuestionnaireUsage.write`: trace entries go in,
# and the sections of the descriptions come out.
module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Verifies how the group summary lists each kind of source, the search check,
    # and which sources it leaves out.
    class WritesSourceTest < Minitest::Test
      include WriteFixtures

      def test_a_launch_context_lists_its_items_under_the_questionnaire
        assert summary([launch_entry]).end_with?(<<~MARKDOWN)
          - **#{FORM_TITLE}**
            - **Launch context patient**: the Patient the form is opened for
              - **Date of birth**: pre-fills the answer; reads birthDate
        MARKDOWN
      end

      def test_a_query_shows_its_request_and_that_the_group_has_the_search_but_no_test
        markdown = summary([query_entry("Patient?gender:not=male&_sort=-birthdate&family={{%name}}")])

        assert_includes markdown, <<~MARKDOWN
          - **Query Patients**: searches Patient resources
              - Request: Patient?gender:not=male&_sort=-birthdate&family={{%name}}
              - This group searches by the same parameters, family + gender, but has no test for it
              - **Name**: pre-fills the answer
        MARKDOWN
      end

      def test_a_test_section_leaves_the_search_check_out
        entry = query_entry("Patient?gender=male&family={{%name}}")
        markdown = section_of_test([entry], "search", search_names: %w[gender family])

        assert_includes markdown, "- Request: Patient?gender=male&family={{%name}}\n    - **Name**"
      end

      def test_a_query_whose_search_the_group_does_not_test
        assert_includes summary([query_entry("Patient?name={{%name}}&_count=1")]),
                        "- A search by name; this group tests _id, family + gender\n"
      end

      def test_a_group_without_searches_says_only_what_the_query_searches_by
        markdown = summary([query_entry("Patient?_id=1")], group: patient_group(searches: []))

        assert_includes markdown, "- A search by _id\n"
      end

      def test_a_query_no_item_reads_is_shown_only_when_it_includes_other_resources
        assert_includes summary([query_entry(LOCATION_QUERY, item_uses: [])]),
                        "- No item reads its results; it fetches PractitionerRole:location through _include\n"
        assert_empty summary([query_entry("Patient?_id=1", item_uses: [])])
      end

      def test_sources_no_item_uses_are_left_out
        assert_empty summary([launch_entry(item_uses: []), include_entry(LOCATION_QUERY, item_uses: [])])
      end

      def test_an_include_entry
        entry = include_entry(LOCATION_QUERY, include: "PractitionerRole:location",
                                              item_uses: [ItemUse.new(link_id: "loc", text: "Location")])

        assert_includes summary([entry]), <<~MARKDOWN
          - **Query Roles**: fetches Patient resources through _include=PractitionerRole:location
              - Request: #{LOCATION_QUERY}
              - **Location**
        MARKDOWN
      end

      def test_extraction_templates
        create = template_entry(patch: false, template_codes: ["http://loinc.org|8302-2"])
        markdown = summary([create, template_entry(patch: true, item_uses: [])])

        assert_includes markdown, "- **Extraction template height**: creates a new Patient with code " \
                                  "http://loinc.org|8302-2 from the answers\n    " \
                                  "- **Height**: its answers fill the template\n"
        assert_includes markdown, "- **Extraction template height**: updates an existing Patient with a " \
                                  "FHIRPath Patch\n    - Its answers come from the whole form\n"
      end

      def test_questionnaires_with_the_same_title_show_their_version
        assembled = launch_entry(header: form_header.with(version: "0.1.0-assembled"))
        markdown = summary([launch_entry, assembled])

        assert_includes markdown, "- **#{FORM_TITLE}, version 0.1.0**\n"
        assert_includes markdown, "- **#{FORM_TITLE}, version 0.1.0-assembled**\n"
      end

      def test_untitled_questionnaires_with_the_same_url_show_their_version
        untitled = form_header.with(title: nil)
        markdown = summary([launch_entry(header: untitled),
                            launch_entry(header: untitled.with(version: "0.2.0"))])

        assert_includes markdown, "- **#{FORM_URL}, version 0.1.0**\n"
        assert_includes markdown, "- **#{FORM_URL}, version 0.2.0**\n"
      end

      def test_a_query_whose_only_include_is_not_traced_is_left_out
        query = "PractitionerRole?_id=1&_include:iterate=PractitionerRole:location"

        assert_empty summary([query_entry(query, item_uses: [])])
      end

      def test_a_compartment_search_selects_by_its_compartment
        group = patient_group(searches: [{ names: %w[patient code] }])

        assert_includes summary([query_entry("Patient/{{%patient.id}}/Observation?code=x")], group:),
                        "- This group searches by the same parameters, patient + code, but has no test for it\n"
      end

      def test_questionnaires_without_a_url_stay_apart
        first = launch_entry(header: form_header.with(url: nil, id: "first"))
        second = launch_entry(header: FormHeader.new(version: "0.1.0", id: "second"))
        markdown = summary([first, second, launch_entry(header: FormHeader.new)])

        assert_includes markdown, "- **#{FORM_TITLE}**\n"
        assert_includes markdown, "- **second**\n"
        assert_includes markdown, "- **Untitled questionnaire**\n"
      end

      def test_a_read_says_it_reads_one_resource
        entry = query_entry("Patient/{{%patient.id}}")

        assert_includes summary([entry]), "- **Query Patients**: reads one Patient by id\n"
      end
    end

    # Verifies the item lines of a source. `WritesCheckedElementTest` covers which
    # read paths count as checked.
    class WritesItemTest < Minitest::Test
      include WriteFixtures

      def test_a_usage_on_the_root_is_named_as_the_whole_form
        root = ItemUse.new(extension: "itemExtractionContext", reads: ["name"])
        markdown = summary([launch_entry(item_uses: [root])])

        assert_includes markdown, "- **The whole form**: sets the extraction context; reads name (not checked)\n"
      end

      def test_an_item_without_text_is_named_by_its_link_id
        markdown = summary([launch_entry(item_uses: [ItemUse.new(link_id: "dob", text: " ", extension: "maxValue")])])

        assert_includes markdown, "- **dob**: maxValue\n"
      end

      def test_markdown_in_an_item_text_is_escaped
        markdown = summary([launch_entry(item_uses: [ItemUse.new(link_id: "dob", text: "Date  *of*\n birth_x")])])

        assert_includes markdown, "- **Date \\*of\\* birth\\_x**\n"
      end

      def test_items_beyond_the_limit_are_counted
        item_uses = (1..27).map { |index| ItemUse.new(link_id: "item-#{index}", text: "Item #{index}") }
        markdown = summary([launch_entry(item_uses:)])

        assert_includes markdown, "**Item 25**"
        refute_includes markdown, "**Item 26**"
        assert_includes markdown, "- and 2 more items\n"
      end
    end

    # Verifies the element lists of the Must Support section and the group summary.
    class WritesElementTest < Minitest::Test
      include WriteFixtures

      def test_lists_each_element_with_the_items_that_read_it
        entry = launch_entry(item_uses: [reading("dob", "Date of birth", "birthDate"),
                                         reading("age", "Age", "birthDate"),
                                         reading("dob", "Date of birth", "birthDate",
                                                 extension: "calculatedExpression"),
                                         reading("contact", "Contact", "contact")])

        assert must_support([entry]).end_with?(<<~MARKDOWN)
          - **#{FORM_TITLE}**
            - **birthDate**: Date of birth, Age
        MARKDOWN
        assert summary([entry]).end_with?("- **#{FORM_TITLE}**\n  - **contact**: Contact\n")
      end

      def test_extensions_are_named_as_in_the_item_lines
        entry = launch_entry(item_uses: [reading("ind", "Status", "extension[url=#{INDIGENOUS_STATUS}].value"),
                                         reading("pro", "Pronouns", "extension[url=#{PRONOUNS}].value")])

        assert_includes must_support([entry]), "- **extension:indigenousStatus.value**: Status"
        assert_includes summary([entry]), "- **extension[individual-pronouns].value**: Pronouns"
      end

      def test_items_beyond_the_limit_are_counted
        item_uses = (1..12).map { |index| reading("item-#{index}", "Item #{index}", "birthDate") }

        assert must_support([launch_entry(item_uses:)]).end_with?("Item 10, and 2 more\n")
      end

      def test_the_must_support_section_has_a_heading_or_is_left_out
        assert must_support([launch_entry]).start_with?("## Used in questionnaires\n\nItems in these questionnaires")
        assert_empty must_support([launch_entry(reads: ["contact"])])
      end

      private

      def must_support(entries)
        section_of_test(entries, "must_support")
      end

      def reading(link_id, text, *reads, extension: "initialExpression")
        ItemUse.new(link_id:, text:, extension:, reads:)
      end
    end

    # Verifies the rest of the group summary: the questionnaires with the tests
    # that list them, and what no test checks.
    class WritesSummaryTest < Minitest::Test
      include WriteFixtures

      def test_names_the_tests_that_list_each_questionnaire
        markdown = summary([launch_entry], group: group_with("read", "must_support"))

        assert_includes markdown, "- **#{FORM_TITLE}**: see the read and Must Support tests\n"
        refute_includes markdown, "**Not tested by this group**"
      end

      def test_lists_the_sources_no_test_makes_with_the_search_check
        markdown = summary([query_entry("Patient?name={{%name}}")])

        assert_includes markdown, "- **#{FORM_TITLE}**: no test in this group makes its requests\n"
        assert_includes markdown, <<~MARKDOWN
          **Not tested by this group**

          No test in this group makes these requests or writes these resources, so nothing checks what these forms get from them.

          - **#{FORM_TITLE}**
            - **Query Patients**: searches Patient resources
              - Request: Patient?name={{%name}}
              - A search by name; this group tests _id, family + gender
        MARKDOWN
      end

      def test_lists_the_elements_no_test_checks
        entry = launch_entry(reads: %w[birthDate contact])

        assert summary([entry], group: group_with("read")).end_with?(<<~MARKDOWN)
          **Elements not checked**

          The profile neither marks these elements Must Support nor requires them, so no test checks that the server returns them.

          - **#{FORM_TITLE}**
            - **contact**: Date of birth
        MARKDOWN
      end

      def test_is_left_out_when_no_entry_is_shown
        assert_empty summary([launch_entry(item_uses: [])])
      end

      private

      def group_with(*kinds)
        patient_group.tap do |group|
          kinds.each { |kind| group.add_test(id: "patient_#{kind}", file_name: "#{kind}.rb", kind:) }
        end
      end
    end

    # Verifies which element paths a group's tests check, and how sections
    # name them, through the item line of an entry no test makes the request of.
    class WritesCheckedElementTest < Minitest::Test
      include WriteFixtures

      INDIGENOUS = "extension[url=#{INDIGENOUS_STATUS}]".freeze
      PRONOUN = "extension[url=#{PRONOUNS}]".freeze

      def test_must_support_and_required_elements_and_id_count_as_checked
        assert_shown patient_group, "birthDate" => "birthDate", "contact" => "contact (not checked)",
                                    "gender" => "gender", "id" => "id", "contact.id" => "contact.id (not checked)",
                                    "contact.name.family" => "contact.name.family (not checked)"
        assert_shown group(elements: ["contact.name"]), "contact.name" => "contact.name"
        assert_shown group(elements: ["contact"]), "contact.name" => "contact.name (not checked)"
        assert_shown group(mandatory: ["Patient.contact.name"]), "contact.name" => "contact.name"
        assert_shown InfernoSuiteGenerator::Generator::GroupMetadata.new(resource: "Patient",
                                                                         profile_url: AU_CORE_PATIENT),
                     "id" => "id", "birthDate" => "birthDate (not checked)"
      end

      def test_a_choice_element_is_compared_by_the_element
        assert_shown patient_group, "deceased" => "deceased", "deceasedBoolean" => "deceasedBoolean",
                                    "deceasedDateTime.value" => "deceasedDateTime.value (not checked)"
        assert_shown group(elements: ["value[x]:valueQuantity.value"]),
                     "valueQuantity.value" => "valueQuantity.value",
                     "valueQuantity.unit" => "valueQuantity.unit (not checked)"
        assert_shown group(elements: ["component.value[x]"]), "component.valueQuantity" => "component.valueQuantity",
                                                              "valueQuantity" => "valueQuantity (not checked)"
        assert_shown group(elements: ["value[x]"]), "values" => "values (not checked)"
      end

      def test_a_must_support_extension_and_its_value_count_as_checked_by_their_slice_name
        assert_shown patient_group,
                     INDIGENOUS => "extension:indigenousStatus",
                     "#{INDIGENOUS}.value" => "extension:indigenousStatus.value",
                     "#{INDIGENOUS}.valueCoding" => "extension:indigenousStatus.valueCoding",
                     "#{INDIGENOUS}.value.code" => "extension:indigenousStatus.value.code (not checked)",
                     "#{PRONOUN}.extension[url=value].value" =>
                       "extension[individual-pronouns].extension[value].value (not checked)"
      end

      def test_only_the_value_part_of_a_complex_extension_counts_as_checked
        slice = "extension:individualPronouns"

        assert_shown group(extensions: [{ id: "Patient.extension:individualPronouns", url: PRONOUNS }]),
                     "#{PRONOUN}.extension[url=value]" => "#{slice}.extension[value]",
                     "#{PRONOUN}.extension[url=value].value" => "#{slice}.extension[value].value",
                     "#{PRONOUN}.extension[url=value].value.text" =>
                       "#{slice}.extension[value].value.text (not checked)",
                     "#{PRONOUN}.extension[url=comment]" => "#{slice}.extension[comment] (not checked)",
                     "#{PRONOUN}.extension[url=comment].value" => "#{slice}.extension[comment].value (not checked)",
                     "#{PRONOUN}.extension[url=period].value.start" =>
                       "#{slice}.extension[period].value.start (not checked)"
      end

      def test_an_extension_slice_counts_under_its_parent_only
        assert_shown group(extensions: [{ id: "Patient.address.extension:state", url: INDIGENOUS_STATUS }]),
                     "address.#{INDIGENOUS}" => "address.extension:state",
                     INDIGENOUS => "extension[indigenous-status] (not checked)"
        assert_shown group(extensions: [{ id: "Patient.modifierExtension:status", url: INDIGENOUS_STATUS }]),
                     "modifierExtension[url=#{INDIGENOUS_STATUS}]" => "modifierExtension:status"
      end

      private

      # Asserts how the group summary shows each path the Date of birth item reads.
      def assert_shown(group, shown)
        shown.each do |path, expected|
          assert_includes summary([launch_entry(reads: [path])], group:),
                          "- **Date of birth**: pre-fills the answer; reads #{expected}\n", path
        end
      end

      def group(elements: [], mandatory: [], extensions: [])
        InfernoSuiteGenerator::Generator::GroupMetadata.new(
          resource: "Patient", profile_url: AU_CORE_PATIENT, mandatory_elements: mandatory,
          must_supports: { elements: elements.map { |path| { path: } }, extensions: }
        )
      end
    end

    # Verifies which tests list each entry in their descriptions.
    class WritesTestedByTest < Minitest::Test
      include WriteFixtures

      def setup
        @patient = patient_group
        add_test(@patient, "patient_read", "read")
        add_test(@patient, "patient_must_support", "must_support")
      end

      def test_an_entry_is_listed_by_its_request_test_and_the_must_support_test_it_reads_for
        result = written([launch_entry], @patient)

        assert_equal %w[patient_read patient_must_support], result.tested_by
        assert_includes result.descriptions.for_test(@patient, "patient_read").join, "**Launch context patient**"
        assert_includes result.descriptions.for_test(@patient, "patient_must_support").join,
                        "**birthDate**: Date of birth"
      end

      def test_an_entry_that_reads_no_checked_element_skips_the_must_support_test
        assert_equal %w[patient_read], tested_by(launch_entry(reads: ["contact"]), group: @patient)
      end

      def test_a_group_without_a_must_support_test_lists_the_request_only
        group = patient_group
        add_test(group, "patient_read", "read")

        assert_equal %w[patient_read], tested_by(launch_entry, group:)
      end

      def test_an_entry_that_is_not_shown_is_listed_by_no_test
        assert_empty tested_by(launch_entry(item_uses: []), group: @patient)
      end

      def test_an_entry_with_no_test_for_its_request_is_listed_by_no_test
        assert_empty tested_by(launch_entry(reads: ["contact"]))
      end

      def test_a_group_no_entry_links_to_is_left_out
        result = write(Trace.new, [@patient])

        assert_empty result.tested_by
        assert_empty result.descriptions.for(@patient)
      end

      def test_two_equal_entries_of_a_group_stay_apart
        section = written([launch_entry, launch_entry], @patient).descriptions.for_test(@patient, "patient_read")

        assert_equal 2, section.join.scan("**Launch context patient**").size
      end

      def test_a_shared_include_is_listed_once_by_its_test
        role = build_group_metadata(name: "role", resource: "PractitionerRole", profile_url: "role", title: "Role")
        add_test(role, "role_include", "include", search_names: ["practitioner"], include_targets: ["Observation"])
        first, second = %w[first second].map do |name|
          build_group_metadata(name: "obs_#{name}", resource: "Observation", profile_url: name)
        end
        entry = include_entry("PractitionerRole?practitioner={{%user.id}}&_include=PractitionerRole:location")
        result = write(trace_of([entry], [first, second]), [role, first, second])

        assert_equal 1, result.descriptions.for_test(role, "role_include").join.scan("**Query Roles**").size
        assert_equal ["role_include"], result.tested_by
      end
    end

    # Verifies which test makes the request of each kind of source.
    class WritesRequestTest < Minitest::Test
      include WriteFixtures

      ROLE_QUERY = "PractitionerRole?practitioner={{%user.id}}&_include=PractitionerRole:location"

      def setup
        @patient = group("Patient", read: {}, create: {}, update: { option: "update" },
                                    search: [{ search_names: %w[family gender] }])
        @role = group("PractitionerRole", include: [{ search_names: ["_id"], include_targets: ["Location"] },
                                                    { search_names: ["practitioner"],
                                                      include_targets: ["Location"] }])
        @location = group("Location")
        @groups = [@patient, @role, @location]
      end

      def test_a_launch_context_and_a_read_go_to_the_read_test
        assert_equal ["patient_read"], route(@patient, launch_entry)
        assert_equal ["patient_read"], route(@patient, query_entry("Patient/{{%patient.id}}"))
      end

      def test_a_search_goes_to_the_search_test_by_the_same_parameters_in_any_order
        entry = query_entry("Patient?gender=male&family={{%name}}&_count=1")

        assert_equal ["patient_search_1"], route(@patient, entry)
        assert_includes summary_of(@patient, entry), "see the search by family + gender test"
      end

      def test_a_search_no_test_makes_goes_nowhere
        assert_empty route(@patient, query_entry("Patient?name=x"))
        assert_empty route(@patient, query_entry("Patient?_sort=-birthdate"))
      end

      def test_an_include_goes_to_the_include_test_of_the_searching_group
        entry = include_entry(ROLE_QUERY)

        assert_equal ["practitionerrole_include_2"], route(@location, entry)
        assert_includes summary_of(@location, entry), "see the search with _include in PractitionerRole test"
      end

      def test_an_include_falls_back_to_any_include_test_for_its_type
        query = "PractitionerRole?organization=x&_include=PractitionerRole:location"

        assert_equal ["practitionerrole_include_1"], route(@location, include_entry(query))
      end

      def test_templates_go_to_the_create_test_or_for_a_patch_to_the_patch_then_update_test
        assert_equal ["patient_create"], route(@patient, template_entry(patch: false))
        assert_equal ["patient_update"], route(@patient, template_entry(patch: true))
        assert_empty route(@location, template_entry(patch: false))
      end

      def test_a_patch_ignores_an_update_test_that_creates_a_new_resource
        encounter = group("Encounter", update: [{ option: "update_new" }, { option: "update" }])
        @groups << encounter

        assert_equal ["encounter_update_2"], route(encounter, template_entry(patch: true))
      end

      private

      # The ids of the tests that list the entry traced for the group.
      def route(group, entry)
        write(trace_of([entry], [group]), @groups).tested_by
      end

      def summary_of(group, entry)
        write(trace_of([entry], [group]), @groups).descriptions.for(group).join
      end

      # A group with tests of these kinds, each kind with one details hash or a list of them.
      def group(resource, **tests)
        InfernoSuiteGenerator::Generator::GroupMetadata.new(resource:, profile_url: resource, title: resource,
                                                            searches: []).tap do |group|
          tests.each do |kind, details|
            Array.wrap(details).each.with_index(1) do |test_details, index|
              id = [resource.downcase, kind, (index if details.is_a?(Array))].compact.join("_")
              add_test(group, id, kind.to_s, **test_details)
            end
          end
        end
      end
    end

    # Verifies an entry traced for two Observation groups, of which only the
    # second checks `status` and slices the Indigenous Status extension, has
    # one answer for both.
    class WritesSharedEntryTest < Minitest::Test
      include WriteFixtures

      UNCHECKING = "http://example.org/StructureDefinition/obs-unchecking"
      CHECKING = "http://example.org/StructureDefinition/obs-checking"
      READS = "reads status, note (not checked), extension:indigenousStatus.value\n"

      def setup
        @unchecking = observation_group("unchecking", UNCHECKING, elements: [])
        @checking = observation_group("checking", CHECKING, elements: [{ path: "status" }],
                                                            extensions: [{ id: "Observation.extension:indigenousStatus",
                                                                           url: INDIGENOUS_STATUS }])
        entry = launch_entry(reads: ["status", "note", "extension[url=#{INDIGENOUS_STATUS}].value"])
        @written = write(trace_of([entry], [@unchecking, @checking]), [@unchecking, @checking])
      end

      def test_every_group_shows_an_element_as_checked_and_named_as_the_group_that_checks_it
        [@unchecking, @checking].each { |group| assert_includes text { |written| written.for(group) }, READS }
      end

      def test_only_the_group_that_checks_an_element_lists_it_in_its_must_support_test
        assert_equal ["checking_must_support"], @written.tested_by
        assert_empty(text { |written| written.for_test(@unchecking, "unchecking_must_support") })
        assert_includes text { |written| written.for_test(@checking, "checking_must_support") },
                        "- **status**: Date of birth\n  - **extension:indigenousStatus.value**: Date of birth"
      end

      private

      # An Observation group with a Must Support test.
      def observation_group(name, profile_url, **must_supports)
        build_group_metadata(name: "obs_#{name}", resource: "Observation", profile_url:, must_supports:)
          .tap { |group| add_test(group, "#{name}_must_support", "must_support") }
      end

      # What the block reads from the descriptions. Observation groups are named
      # through the config, as several profiles share the type.
      def text
        with_config_keeper { yield(@written.descriptions).join }
      end
    end
  end
end
