# frozen_string_literal: true

require_relative "questionnaire_usage_query_helpers"

module InfernoSuiteGenerator
  # Query paths and parameter names, namespaced type picks, entry-pick arguments and query variable scope.
  class QuestionnaireUsageQueryPathsTest < Minitest::Test
    include QuestionnaireUsageQueryHelpers

    def search_lines(items, root: [query("Obs", HEIGHT_QUERY)], group: obs_group)
      item_lines(describe(obs_ig(obs_form(root, items)), group).fetch(group)["obs_search_patient_code"])
    end

    def test_namespaced_type_picks_type_the_chain
      items = [item("a", "A", "%Obs.entry.where(resource is FHIR.Observation).resource.value.value",
                    "%Obs.entry.resource.ofType(FHIR.Observation).status"),
               item("b", "B", "%Obs.entry.where(resource.is(FHIR.Patient)).resource.gender")]

      assert_equal ["    - Request: #{HEIGHT_QUERY}\n",
                    "    - **A**: pre-fills the answer; reads value.value, status (not checked)\n"], search_lines(items)
    end

    def test_resource_type_pick_types_the_chain
      items = [item("a", "A", "%Obs.entry.resource.where(resourceType = 'Observation').status"),
               item("b", "B", "%Obs.entry.resource.where(resourceType = 'Patient').name")]

      assert_equal ["    - Request: #{HEIGHT_QUERY}\n",
                    "    - **A**: pre-fills the answer; reads status (not checked)\n"], search_lines(items)
    end

    def test_entry_pick_arguments_read_paths_on_the_resource
      items = [item("a", "A", "%Obs.entry.where(resource.status = 'final').resource.value.value")]

      assert_equal "    - **A**: pre-fills the answer; reads value.value, status (not checked)\n",
                   search_lines(items).last
    end

    def test_item_query_shadows_an_outer_fhirpath_variable
      root = [launch("patient", "Patient"), variable("Obs", "%patient.name")]
      items = [item("a", "A", query("Obs", HEIGHT_QUERY), "%Obs.entry.resource.value.value")]

      assert_equal "    - **A**: pre-fills the answer; reads value.value\n", search_lines(items, root:).last
      assert_empty @log
    end

    def test_chained_parameter_keeps_its_chain_without_the_modifier
      text = "Observation?subject:Patient.name=Smith&code=#{LOINC}|8302-2"
      group = obs_group(tests: [%w[code subject.name]])
      entry = describe(obs_ig(height_form(text)), group).fetch(group)

      assert_includes entry["obs_search_code_subject.name"], "Request: #{text}\n"
    end

    def test_history_after_an_id_is_a_search_and_an_empty_path_is_no_source
      group = obs_group
      entry = describe(obs_ig(height_form("Observation/{{%id}}/_history")), group).fetch(group)

      assert_includes entry[:group], "  - **Query Obs**: searches Observation resources\n"
      assert_empty describe(obs_ig(height_form("?code=#{LOINC}|8302-2")), group)
      assert_empty @log
    end
  end
end
