# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # Verifies the `UsageSection` Markdown: what it says about each source, the
    # search and Must Support checks, and the item table.
    class UsageSectionTest < Minitest::Test
      include TracerFixtures

      INDIGENOUS_STATUS = "http://hl7.org.au/fhir/StructureDefinition/indigenous-status"
      PRONOUNS = "http://hl7.org/fhir/StructureDefinition/individual-pronouns"
      LOCATION_QUERY = "PractitionerRole?_id={{%role.id}}&_include=PractitionerRole:location"

      def test_a_must_support_extension_is_named_by_its_slice
        markdown = section([launch_entry(reads: ["extension[url=#{INDIGENOUS_STATUS}].value"])])

        assert_includes markdown, "| `dob` Date of birth | pre-fills the answer | `extension:indigenousStatus.value` |"
        assert_includes markdown, "✅ Every element it reads is Must Support or required."
      end

      def test_an_extension_that_is_not_must_support_keeps_its_url_and_is_flagged
        markdown = section([launch_entry(reads: ["extension[url=#{PRONOUNS}].value"])])

        assert_includes markdown, "`extension[url=#{PRONOUNS}].value` ⚠️ |"
        assert_includes markdown, "⚠️ Neither Must Support nor required: `extension[url=#{PRONOUNS}].value`."
      end

      def test_mandatory_elements_and_id_count_as_checked
        markdown = section([launch_entry(reads: %w[gender id contact])])

        assert_includes markdown, "| `gender`, `id`, `contact` ⚠️ |"
        assert_includes markdown, "⚠️ Neither Must Support nor required: `contact`."
      end

      def test_a_query_whose_search_the_group_does_not_test
        markdown = section([query_entry("Patient?name={{%name}}&_count=1")])

        assert_includes markdown, "⚠️ This group does not test a search by `name`. It tests `_id`, `family + gender`."
      end

      def test_search_modifiers_and_result_params_are_ignored
        markdown = section([query_entry("Patient?gender:not=male&_sort=-birthdate&family={{%name}}")])

        assert_includes markdown, "✅ This group tests the same search: `family + gender`."
      end

      def test_a_group_without_searches_says_only_that_the_search_is_not_tested
        markdown = section([query_entry("Patient?_id=1")], group: patient_group(searches: []))

        assert_includes markdown, "⚠️ This group does not test a search by `_id`.\n"
      end

      def test_a_query_no_item_reads_says_what_it_includes
        markdown = section([query_entry(LOCATION_QUERY, used_in: [])])

        assert_includes markdown, "No item reads the Patient resources it returns. " \
                                  "It is there to fetch `PractitionerRole:location` through `_include`."
      end

      def test_an_include_entry
        entry = { source: "include", questionnaire_title: FORM_TITLE, name: "Roles", query: LOCATION_QUERY,
                  include: "PractitionerRole:location", used_in: [] }

        assert_includes section([entry]), "**Included by query `Roles`** through " \
                                          "`_include=PractitionerRole:location`: `#{LOCATION_QUERY}`\n\n" \
                                          "No item reads the included Patient resources."
      end

      def test_a_launch_context_with_no_items
        assert_includes section([launch_entry(used_in: [])]),
                        "**Launch context `patient`**: the Patient the form is opened for.\n\nNo item reads it."
      end

      def test_extraction_templates
        create = template_entry(patch: false, template_codes: ["http://loinc.org|8302-2"])
        markdown = section([create, template_entry(patch: true, used_in: [])])

        assert_includes markdown, "**Extraction template `height`**: creates a new Patient with code " \
                                  "`http://loinc.org|8302-2` from the answers."
        assert_includes markdown, "| `height` Height | is extracted from its answers | — |"
        assert_includes markdown, "**Extraction template `height`**: updates an existing Patient with a " \
                                  "FHIRPath Patch.\n\nIt is extracted from the answers of the whole form."
      end

      def test_an_unknown_extension_is_shown_by_name
        markdown = section([launch_entry(used_in: [{ link_id: "dob", text: "Date of birth", extension: "maxValue" }])])

        assert_includes markdown, "| `dob` Date of birth | `maxValue` | — |"
      end

      def test_a_pipe_in_an_item_text_is_escaped_for_the_table
        markdown = section([launch_entry(used_in: [{ link_id: "dob", text: "Date | Time" }])])

        assert_includes markdown, "| `dob` Date \\| Time |"
      end

      def test_rows_beyond_the_limit_are_counted
        used_in = (1..27).map { |index| { link_id: "item-#{index}", text: "Item #{index}" } }
        markdown = section([launch_entry(used_in:)])

        assert_includes markdown, "| `item-25` Item 25 |"
        refute_includes markdown, "`item-26`"
        assert_includes markdown, "…and 2 more items, listed in `plugins.yml`."
      end

      private

      def section(entries, group: patient_group)
        UsageSection.new(entries, group).markdown
      end

      def launch_entry(reads: ["birthDate"],
                       used_in: [{ link_id: "dob", text: "Date of birth", extension: "initialExpression", reads: }])
        { source: "launch_context", questionnaire_title: FORM_TITLE, name: "patient", elements_read: reads, used_in: }
      end

      def query_entry(query, used_in: [{ link_id: "name", text: "Name", extension: "initialExpression" }])
        { source: "query", questionnaire_title: FORM_TITLE, name: "Patients", query:, used_in: }
      end

      def template_entry(patch:, template_codes: [], used_in: [{ link_id: "height", text: "Height",
                                                                 extension: "templateExtract" }])
        { source: "template_extract", questionnaire_title: FORM_TITLE, name: "height", patch:, template_codes:,
          used_in: }
      end

      def patient_group(searches: [{ names: ["_id"] }, { names: %w[family gender] }])
        Generator::GroupMetadata.new(
          resource: "Patient", profile_url: AU_CORE_PATIENT, searches:, mandatory_elements: ["Patient.gender"],
          must_supports: { elements: [{ path: "birthDate" }],
                           extensions: [{ id: "Patient.extension:indigenousStatus", url: INDIGENOUS_STATUS }] }
        )
      end
    end
  end
end
