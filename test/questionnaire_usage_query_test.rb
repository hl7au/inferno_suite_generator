# frozen_string_literal: true

require_relative "questionnaire_usage_helpers"

module InfernoSuiteGenerator
  class QuestionnaireUsageQueryTest < Minitest::Test
    include QuestionnaireUsageHelpers

    LOINC = "http://loinc.org"
    HEIGHT_URL = "http://example.org/StructureDefinition/body-height"
    WEIGHT_URL = "http://example.org/StructureDefinition/body-weight"
    HEIGHT_QUERY = "Observation?code=#{LOINC}|8302-2&patient={{%patient.id}}&_sort=-date".freeze
    COMPARTMENT_QUERY = "Patient/{{%patient.id}}/Observation?code=#{LOINC}|8302-2&date=gt2020".freeze
    NOT_CHECKED_SENTENCE = "Elements marked (not checked) are neither Must Support nor required by the profile, " \
                           "so this group's tests do not check them."
    SEARCH_INTRO = "These questionnaires in the IG make this search. #{READS} #{NOT_CHECKED_SENTENCE}".freeze
    HEIGHT_ITEM = "    - **Body height**: pre-fills the answer; reads value.value, note.text (not checked)\n"

    def query(name, text)
      { "url" => "http://hl7.org/fhir/StructureDefinition/variable",
        "valueExpression" => { "name" => name, "language" => "application/x-fhir-query", "expression" => text } }
    end

    def obs_form(root, items = [item("height", "Body height", "%Latest.value.value", "%Latest.note.text")])
      form(items, contexts: root, title: "Vitals form", url: "http://example.org/Questionnaire/vitals")
    end

    def height_form(text = HEIGHT_QUERY)
      obs_form([query("Obs", text), variable("Latest", "%Obs.entry.resource.first()")])
    end

    # A profile fixing Observation.code by patternCodeableConcept, or by a coding slice when sliced.
    def profile(url, code, sliced: false)
      elements = if sliced
                   [{ "id" => "Observation.code.coding:loinc.system", "path" => "Observation.code.coding.system",
                      "fixedUri" => LOINC },
                    { "id" => "Observation.code.coding:loinc.code", "path" => "Observation.code.coding.code",
                      "fixedCode" => code }]
                 else
                   [{ "id" => "Observation.code", "path" => "Observation.code",
                      "patternCodeableConcept" => { "coding" => [{ "system" => LOINC, "code" => code }] } }]
                 end
      FHIR::StructureDefinition.new("resourceType" => "StructureDefinition", "url" => url, "type" => "Observation",
                                    "snapshot" => { "element" => elements })
    end

    def obs_group(url = HEIGHT_URL, searches: [%w[patient code]], tests: [%w[patient code]])
      GroupMetadata.new(
        resource: "Observation", profile_url: url, profile_name: url.split("/").last, title: "Observation Tests",
        searches: searches.map { |names| { names: } }, mandatory_elements: [],
        must_supports: { extensions: [], slices: [], elements: [{ path: "value[x].value" }] }
      ).tap do |group|
        group.add_test(id: "obs_must_support", file_name: "ms.rb", kind: "must_support")
        tests.each do |names|
          group.add_test(id: "obs_search_#{names.join("_")}", file_name: "search.rb", kind: "search",
                         search_names: names)
        end
      end
    end

    def obs_ig(*forms, profiles: [profile(HEIGHT_URL, "8302-2")])
      ig(*forms).tap { |resources| profiles.each { |structure| resources.add(structure) } }
    end

    def query_block(heading, text, *lines)
      "- **Vitals form**\n  - **Query Obs**: #{heading}\n    - Request: #{text}\n#{lines.join}"
    end

    def not_tested(entry) = entry[:group][/#{Regexp.escape(NOT_TESTED)}\n\n(.*?\n)(?:\n|\z)/m, 1]

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

      assert_includes read, "  - **Query Pat**: reads one Patient by id\n    - Request: #{text}\n    - **Family name**: " \
                            "pre-fills the answer; reads name.family, entry.resource.gender (not checked)\n"
    end

    def test_bundle_chains_read_only_through_entry_and_resource
      root = [query("Q", "Patient?name=Smith"), variable("Picked", "%Q.entry.where(resource is Patient).first()")]
      items = [item("total", "Total", "%Q.total"), item("count", "Count", "%Q.entry.count()"),
               item("address", "Address", "%Picked.resource.address"),
               item("typed", "Typed", "%Q.entry.where(resource.is(Patient)).resource.gender",
                    "%Q.entry[0].resource.ofType(Patient).birthDate"),
               item("other", "Other", "%Q.entry.where(resource is Observation).resource.status")]
      patient = group(tests: %w[read]).tap do |metadata|
        metadata.add_test(id: "patient_search_name", file_name: "s.rb", kind: "search", search_names: %w[name])
      end
      lines = item_lines(patient_entry(obs_form(root, items), patient:)["patient_search_name"])

      assert_equal ["    - Request: Patient?name=Smith\n", "    - **Total**: pre-fills the answer\n",
                    "    - **Count**: pre-fills the answer\n",
                    "    - **Address**: pre-fills the answer; reads address (not checked)\n",
                    "    - **Typed**: pre-fills the answer; reads gender (not checked), birthDate (not checked)\n"],
                   lines
    end

    def untested_line(group)
      not_tested(describe(obs_ig(height_form(COMPARTMENT_QUERY)), group).fetch(group))
    end

    def compared(line)
      query_block("searches Observation resources", COMPARTMENT_QUERY, "    - #{line}\n", HEIGHT_ITEM)
    end

    def test_untested_search_with_the_same_group_searches_says_it_has_no_test
      assert_equal compared("This group searches by the same parameters, patient + code + date, but has no test " \
                            "for it"), untested_line(obs_group(searches: [%w[code patient date]], tests: []))
    end

    def test_untested_search_lists_the_group_searches_not_the_recorded_tests
      group = obs_group(searches: [%w[status patient], %w[_id]], tests: [%w[patient]])

      assert_equal compared("A search by patient + code + date; this group tests status + patient, _id"),
                   untested_line(group)
    end

    def test_untested_search_without_group_searches_has_no_tail
      assert_equal compared("A search by patient + code + date"), untested_line(obs_group(searches: [], tests: [%w[_id]]))
    end

    def test_summary_label_uses_the_recorded_test_order
      group = obs_group(tests: [%w[date code patient]])
      entry = describe(obs_ig(height_form(COMPARTMENT_QUERY)), group).fetch(group)

      assert_includes entry[:group], "- **Vitals form**: see the search by date + code + patient and Must Support tests\n"
      assert_nil not_tested(entry)
    end

    def test_query_without_search_parameters_has_no_test_and_no_comparison
      group = obs_group
      untested = not_tested(describe(obs_ig(height_form("Observation?_count=1")), group).fetch(group))

      assert_equal query_block("searches Observation resources", "Observation?_count=1", HEIGHT_ITEM), untested
    end

    def two_profiles(text)
      height = obs_group
      weight = obs_group(WEIGHT_URL)
      result = describe(obs_ig(height_form(text), profiles: [profile(HEIGHT_URL, "8302-2"),
                                                             profile(WEIGHT_URL, "29463-7", sliced: true)]),
                        height, weight)
      result.transform_keys { |group| group.equal?(height) ? :height : :weight }
    end

    def test_several_profiles_keep_only_those_whose_codes_overlap
      assert_equal %i[weight], two_profiles("Observation?code=#{LOINC}|29463-7&patient=x").keys
      assert_empty @log
    end

    def test_several_matching_profiles_are_all_kept_and_logged
      assert_equal %i[height weight], two_profiles("Observation?code=8302-2,#{LOINC}|29463-7&patient=x").keys
      assert_equal "Questionnaire usage tracing: Vitals form query Obs matches several profiles: " \
                   "#{HEIGHT_URL}, #{WEIGHT_URL}\n", @log
    end

    def test_no_matching_profile_is_logged_unresolved
      assert_empty two_profiles("Observation?code=#{LOINC}|9999-9&patient=x")
      assert_equal "Questionnaire usage tracing: unresolved Vitals form query Obs: no Observation profile matches " \
                   "code=#{LOINC}|9999-9\n", @log
    end

    def test_code_the_only_profile_fixes_otherwise_gives_nothing_and_is_logged
      assert_equal({}, describe(obs_ig(height_form("Observation?code=#{LOINC}|29463-7&patient=x")), obs_group))
      assert_equal "Questionnaire usage tracing: unresolved Vitals form query Obs: the Observation profile fixes " \
                   "code=#{LOINC}|8302-2, not code=#{LOINC}|29463-7\n", @log
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
