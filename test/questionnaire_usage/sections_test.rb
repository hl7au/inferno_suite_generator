# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Verifies how the group summary lists each kind of source, the search check,
    # and which sources it leaves out.
    class SectionsSourceTest < Minitest::Test
      include TraceEntryFixtures

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
        assert_includes summary([query_entry(LOCATION_QUERY, used_in: [])]),
                        "- No item reads its results; it fetches PractitionerRole:location through _include\n"
        assert_empty summary([query_entry("Patient?_id=1", used_in: [])])
      end

      def test_sources_no_item_uses_are_left_out
        assert_empty summary([launch_entry(used_in: []), launch_entry(used_in: [variable_use])])
      end

      def test_an_include_entry
        entry = include_entry(LOCATION_QUERY, include: "PractitionerRole:location",
                                              used_in: [ItemUse.new(link_id: "loc", text: "Location")])

        assert_includes summary([entry]), <<~MARKDOWN
          - **Query Roles**: fetches Patient resources through _include=PractitionerRole:location
              - Request: #{LOCATION_QUERY}
              - **Location**
        MARKDOWN
      end

      def test_extraction_templates
        create = template_entry(patch: false, template_codes: ["http://loinc.org|8302-2"])
        markdown = summary([create, template_entry(patch: true, used_in: [])])

        assert_includes markdown, "- **Extraction template height**: creates a new Patient with code " \
                                  "http://loinc.org|8302-2 from the answers\n    " \
                                  "- **Height**: its answers fill the template\n"
        assert_includes markdown, "- **Extraction template height**: updates an existing Patient with a " \
                                  "FHIRPath Patch\n    - Its answers come from the whole form\n"
      end

      def test_questionnaires_with_the_same_title_show_their_version
        assembled = launch_entry(header: form_header.merge(questionnaire_version: "0.1.0-assembled"))
        markdown = summary([launch_entry, assembled])

        assert_includes markdown, "- **#{FORM_TITLE}, version 0.1.0**\n"
        assert_includes markdown, "- **#{FORM_TITLE}, version 0.1.0-assembled**\n"
      end

      def test_untitled_questionnaires_with_the_same_url_show_their_version
        untitled = form_header.except(:questionnaire_title)
        markdown = summary([launch_entry(header: untitled),
                            launch_entry(header: untitled.merge(questionnaire_version: "0.2.0"))])

        assert_includes markdown, "- **#{FORM_URL}, version 0.1.0**\n"
        assert_includes markdown, "- **#{FORM_URL}, version 0.2.0**\n"
      end

      def test_a_query_whose_only_include_is_not_traced_is_left_out
        query = "PractitionerRole?_id=1&_include:iterate=PractitionerRole:location"

        assert_empty summary([query_entry(query, used_in: [])])
      end

      def test_a_compartment_search_selects_by_its_compartment
        group = patient_group(searches: [{ names: %w[patient code] }])

        assert_includes summary([query_entry("Patient/{{%patient.id}}/Observation?code=x")], group:),
                        "- This group searches by the same parameters, patient + code, but has no test for it\n"
      end

      def test_questionnaires_without_a_url_stay_apart
        first = launch_entry(header: form_header.except(:questionnaire_url).merge(questionnaire_id: "first"))
        second = launch_entry(header: { questionnaire_version: "0.1.0", questionnaire_id: "second" })
        markdown = summary([first, second])

        assert_includes markdown, "- **#{FORM_TITLE}**\n"
        assert_includes markdown, "- **second**\n"
      end

      def test_a_read_says_it_reads_one_resource
        entry = query_entry("Patient/{{%patient.id}}")

        assert_includes summary([entry]), "- **Query Patients**: reads one Patient by id\n"
      end
    end

    # Verifies the item lines of a source. `CheckedElementsTest` covers which read
    # paths count as checked.
    class SectionsItemTest < Minitest::Test
      include TraceEntryFixtures

      def test_a_usage_on_the_root_is_named_as_the_whole_form
        markdown = summary([launch_entry(used_in: [ItemUse.new(extension: "itemExtractionContext", reads: ["name"])])])

        assert_includes markdown, "- **The whole form**: sets the extraction context; reads name (not checked)\n"
      end

      def test_an_item_without_text_is_named_by_its_link_id
        markdown = summary([launch_entry(used_in: [ItemUse.new(link_id: "dob", extension: "maxValue")])])

        assert_includes markdown, "- **dob**: maxValue\n"
      end

      def test_markdown_in_an_item_text_is_escaped
        markdown = summary([launch_entry(used_in: [ItemUse.new(link_id: "dob", text: "Date *of* birth_x")])])

        assert_includes markdown, "- **Date \\*of\\* birth\\_x**\n"
      end

      def test_items_beyond_the_limit_are_counted
        used_in = (1..27).map { |index| ItemUse.new(link_id: "item-#{index}", text: "Item #{index}") }
        markdown = summary([launch_entry(used_in:)])

        assert_includes markdown, "**Item 25**"
        refute_includes markdown, "**Item 26**"
        assert_includes markdown, "- and 2 more items, listed in questionnaire_usage.yml\n"
      end
    end

    # Verifies the element lists of the Must Support section and the group summary.
    class SectionsElementTest < Minitest::Test
      include TraceEntryFixtures

      def test_lists_each_element_with_the_items_that_read_it
        entry = launch_entry(used_in: [reading("dob", "Date of birth", "birthDate"), reading("age", "Age", "birthDate"),
                                       reading("dob", "Date of birth", "birthDate", extension: "calculatedExpression"),
                                       reading("contact", "Contact", "contact")])

        assert must_support([entry]).end_with?(<<~MARKDOWN)
          - **#{FORM_TITLE}**
            - **birthDate**: Date of birth, Age
        MARKDOWN
        assert summary([entry]).end_with?("- **#{FORM_TITLE}**\n  - **contact**: Contact\n")
      end

      def test_extensions_are_named_as_in_the_item_lines
        entry = launch_entry(used_in: [reading("ind", "Status", "extension[url=#{INDIGENOUS_STATUS}].value"),
                                       reading("pro", "Pronouns", "extension[url=#{PRONOUNS}].value")])

        assert_includes must_support([entry]), "- **extension:indigenousStatus.value**: Status"
        assert_includes summary([entry]), "- **extension[individual-pronouns].value**: Pronouns"
      end

      def test_items_beyond_the_limit_are_counted
        used_in = (1..12).map { |index| reading("item-#{index}", "Item #{index}", "birthDate") }

        assert must_support([launch_entry(used_in:)]).end_with?("Item 10, and 2 more\n")
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
    class SectionsSummaryTest < Minitest::Test
      include TraceEntryFixtures

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
        assert_empty summary([launch_entry(used_in: [])])
      end

      private

      def group_with(*kinds)
        patient_group.tap do |group|
          kinds.each { |kind| group.add_test(id: "patient_#{kind}", file_name: "#{kind}.rb", kind:) }
        end
      end
    end
  end
end
