# frozen_string_literal: true

require_relative "questionnaire_usage_query_helpers"

module InfernoSuiteGenerator
  # x-fhir-query sources: read and search tests, Bundle chains, item queries.
  class QuestionnaireUsageQueryTest < Minitest::Test
    include QuestionnaireUsageQueryHelpers

    def test_search_query_is_listed_by_the_search_test_with_the_same_parameters
      group = obs_group(tests: [%w[code patient]])
      entry = describe(obs_ig(height_form), group).fetch(group)

      assert_equal section(SEARCH_INTRO,
                           query_block("searches Observation resources", HEIGHT_QUERY, HEIGHT_ITEM).chomp),
                   entry["obs_search_code_patient"]
      assert_includes entry[:group], "- **Vitals form**: see the search by code + patient and Must Support tests\n"
    end

    def test_compartment_search_adds_the_compartment_parameter
      text = "Patient/{{%patient.id}}/Observation?code=#{LOINC}|8302-2"
      group = obs_group
      entry = describe(obs_ig(height_form(text)), group).fetch(group)

      assert_includes entry["obs_search_patient_code"], query_block("searches Observation resources", text, HEIGHT_ITEM)
    end

    def test_read_query_goes_to_the_read_test_and_reads_the_resource_directly
      text = "Patient/{{%patient.id}}"
      items = [item("family", "Family name", "%Pat.name.family", "%Pat.entry.resource.gender")]
      read = patient_entry(obs_form([query("Pat", text)], items))["patient_read"]

      assert_includes read, "  - **Query Pat**: reads one Patient by id\n    - Request: #{text}\n    - **Family " \
                            "name**: pre-fills the answer; reads name.family, entry.resource.gender (not checked)\n"
    end

    # Bundle reads: none, through an entry-carrying variable, typed by entry picks, and of another type.
    def bundle_items
      [item("total", "Total", "%Q.total"), item("count", "Count", "%Q.entry.count()"),
       item("address", "Address", "%Picked.resource.address"),
       item("typed", "Typed", "%Q.entry.where(resource.is(Patient)).resource.gender",
            "%Q.entry[0].resource.ofType(Patient).birthDate"),
       item("other", "Other", "%Q.entry.where(resource is Observation).resource.status")]
    end

    def test_bundle_chains_read_only_through_entry_and_resource
      root = [query("Q", "Patient?name=Smith"), variable("Picked", "%Q.entry.where(resource is Patient).first()")]
      patient = group(tests: %w[read]).tap do |metadata|
        metadata.add_test(id: "patient_search_name", file_name: "s.rb", kind: "search", search_names: %w[name])
      end
      lines = item_lines(patient_entry(obs_form(root, bundle_items), patient:)["patient_search_name"])

      assert_equal ["    - Request: Patient?name=Smith\n", "    - **Total**: pre-fills the answer\n",
                    "    - **Count**: pre-fills the answer\n",
                    "    - **Address**: pre-fills the answer; reads address (not checked)\n",
                    "    - **Typed**: pre-fills the answer; reads gender (not checked), birthDate (not checked)\n"],
                   lines
    end

    def test_query_type_without_a_group_is_logged_and_the_rest_is_traced
      root = [query("Cond", "Condition?patient=x"), query("Obs", HEIGHT_QUERY),
              variable("Latest", "%Obs.entry.resource.first()")]
      items = [item("cond", "Condition", "%Cond.entry.resource.code"),
               item("height", "Body height", "%Latest.value.value", "%Latest.note.text")]
      group = obs_group
      entry = describe(obs_ig(obs_form(root, items)), group).fetch(group)

      assert_equal "Questionnaire usage tracing: untraced Vitals form query Cond: no group for Condition\n", @log
      assert_includes entry["obs_search_patient_code"], HEIGHT_ITEM
    end

    def test_item_query_is_traced_and_templates_with_ampersands_do_not_split_parameters
      text = "Observation?patient={{%patient.id & '&code=x'}}&code=#{LOINC}|8302-2"
      items = [item("height", "Body height", query("Obs", text), "%Obs.entry.resource.value.value")]
      group = obs_group
      entry = describe(obs_ig(obs_form([], items)), group).fetch(group)

      assert_includes entry["obs_search_patient_code"],
                      query_block("searches Observation resources", text,
                                  "    - **Body height**: pre-fills the answer; reads value.value\n")
    end
  end
end
