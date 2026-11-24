# frozen_string_literal: true

require_relative "questionnaire_usage_query_helpers"

# MedicationRequest and Medication groups and a form whose query fetches Medication through _include.
module QuestionnaireUsageIncludeHelpers
  include QuestionnaireUsageQueryHelpers

  INCLUDE = "MedicationRequest:medication"
  MEDS_QUERY = "MedicationRequest?patient={{%patient.id}}&_include=#{INCLUDE}".freeze
  INCLUDE_INTRO = "These questionnaires in the IG fetch Medication resources through this search's _include. " \
                  "#{READS} Elements marked (not checked) are neither Must Support nor required by any " \
                  "Medication profile in this suite, so no test checks them.".freeze
  NO_READS = "    - No item reads its results; it fetches #{INCLUDE} through _include\n".freeze
  LABEL = "search with _include in MedicationRequest"
  LINE = "- **Meds form**: see the #{LABEL} test\n".freeze
  MR_CATEGORY = "http://terminology.hl7.org/CodeSystem/medicationrequest-category"
  MR_URL = "http://example.org/StructureDefinition/mr"
  MED_ITEMS = "    - **Medication**: pre-fills the answer; reads code\n    " \
              "- **Dose form**: pre-fills the answer; reads form (not checked)\n"

  def meds_form(root = meds_query, items = med_items)
    form(items, contexts: root, title: "Meds form", url: "http://example.org/Questionnaire/meds")
  end

  def meds_query(text = MEDS_QUERY) = [query("Meds", text)]

  def med_items
    [item("med", "Medication", "%Meds.entry.where(resource is Medication).resource.code"),
     item("dose", "Dose form", "%Meds.entry.resource.ofType(Medication).form")]
  end

  def include_heading(text = MEDS_QUERY, value = INCLUDE)
    "  - **Query Meds**: fetches Medication resources through _include=#{value}\n    - Request: #{text}\n"
  end

  # The query's own lines when no test in the group makes its search.
  def query_lines(text = MEDS_QUERY, *lines)
    "- **Meds form**\n  - **Query Meds**: searches MedicationRequest resources\n    - Request: #{text}\n#{lines.join}"
  end

  def med_group(url = "http://example.org/StructureDefinition/med")
    GroupMetadata.new(
      resource: "Medication", profile_url: url, profile_name: "Medication Profile", title: "Medication Tests",
      searches: [], mandatory_elements: [], must_supports: { extensions: [], slices: [], elements: [{ path: "code" }] }
    ).tap do |group|
      group.add_test(id: "med_read#{url[-1]}", file_name: "read.rb", kind: "read")
      group.add_test(id: "med_ms#{url[-1]}", file_name: "ms.rb", kind: "must_support")
    end
  end

  # A MedicationRequest group with an include test per includes entry: [id, search_names, targets].
  def mr_group(title: "MedicationRequest", url: MR_URL, includes: [["mr_include", %w[patient], %w[Medication]]])
    GroupMetadata.new(resource: "MedicationRequest", profile_url: url, profile_name: "MedicationRequest Profile",
                      title:, searches: [], mandatory_elements: [],
                      must_supports: { extensions: [], slices: [], elements: [] }).tap do |group|
      includes.each do |id, names, targets|
        group.add_test(id:, file_name: "#{id}.rb", kind: "include", search_names: names, include_targets: targets)
      end
    end
  end

  # A MedicationRequest profile fixing category to the code.
  def mr_profile(url, code)
    pattern = { "coding" => [{ "system" => MR_CATEGORY, "code" => code }] }
    element = { "id" => "MedicationRequest.category", "path" => "MedicationRequest.category",
                "patternCodeableConcept" => pattern }
    FHIR::StructureDefinition.new("resourceType" => "StructureDefinition", "url" => url,
                                  "type" => "MedicationRequest", "snapshot" => { "element" => [element] })
  end

  # The profiles of MedicationRequest groups at MR_URL + 1 and + 2.
  def two_mr_profiles = [mr_profile("#{MR_URL}1", "community"), mr_profile("#{MR_URL}2", "outpatient")]

  # The descriptions of the groups for a meds form with these root extensions and items, and extra IG resources.
  def meds_result(groups, root = meds_query, items = med_items, extra: [])
    describe(ig(meds_form(root, items)).tap { |resources| extra.each { |resource| resources.add(resource) } },
             *groups)
  end

  # The first group's entry, traced with a Medication group.
  def meds_entry(group, *, **)
    meds_result([group, med_group], *, **).fetch(group)
  end

  # Also picks Substance, so a target inferred from the form would add a Substance include.
  def med_and_substance_items
    [*med_items, item("sub", "Substance", "%Meds.entry.resource.ofType(Substance).code")]
  end

  def no_reads(*values) = "    - No item reads its results; it fetches #{values.join(", ")} through _include\n"

  def logged(*lines) = lines.map { |line| "Questionnaire usage tracing: #{line}\n" }
end
