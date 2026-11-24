# frozen_string_literal: true

require_relative "questionnaire_usage_helpers"

# Observation groups, profiles fixing Observation.code and forms with x-fhir-query variables.
module QuestionnaireUsageQueryHelpers
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

  def sliced_code(code)
    [{ "id" => "Observation.code.coding:loinc.system", "path" => "Observation.code.coding.system",
       "fixedUri" => LOINC },
     { "id" => "Observation.code.coding:loinc.code", "path" => "Observation.code.coding.code", "fixedCode" => code }]
  end

  # A profile fixing Observation.code by patternCodeableConcept, or by a coding slice when sliced.
  def profile(url, code, sliced: false)
    pattern = { "coding" => [{ "system" => LOINC, "code" => code }] }
    elements = if sliced
                 sliced_code(code)
               else
                 [{ "id" => "Observation.code", "path" => "Observation.code",
                    "patternCodeableConcept" => pattern }]
               end
    FHIR::StructureDefinition.new("resourceType" => "StructureDefinition", "url" => url, "type" => "Observation",
                                  "snapshot" => { "element" => elements })
  end

  # An Observation group with a Must Support test and a search test per tests entry.
  def obs_group(url = HEIGHT_URL, searches: [%w[patient code]], tests: [%w[patient code]])
    GroupMetadata.new(
      resource: "Observation", profile_url: url, profile_name: url.split("/").last, title: "Observation Tests",
      searches: searches.map { |names| { names: } }, mandatory_elements: [],
      must_supports: { extensions: [], slices: [], elements: [{ path: "value[x].value" }] }
    ).tap do |group|
      group.add_test(id: "obs_must_support", file_name: "ms.rb", kind: "must_support")
      tests.each { |names| add_search(group, names) }
    end
  end

  def add_search(group, names)
    group.add_test(id: "obs_search_#{names.join("_")}", file_name: "search.rb", kind: "search", search_names: names)
  end

  def obs_ig(*forms, profiles: [profile(HEIGHT_URL, "8302-2")])
    ig(*forms).tap { |resources| profiles.each { |structure| resources.add(structure) } }
  end

  def query_block(heading, text, *lines)
    "- **Vitals form**\n  - **Query Obs**: #{heading}\n    - Request: #{text}\n#{lines.join}"
  end

  NOT_TESTED_LIST = /#{Regexp.escape(NOT_TESTED)}\n\n(.*?\n)(?:\n|\z)/m

  def not_tested(entry) = entry[:group][NOT_TESTED_LIST, 1]
end
