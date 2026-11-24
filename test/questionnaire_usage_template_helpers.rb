# frozen_string_literal: true

require_relative "questionnaire_usage_include_helpers"

# Forms with sdc-questionnaire-templateExtract on the root and items, contained Observations and a FHIRPath
# Patch Parameters, and groups with create, patch and update tests.
module QuestionnaireUsageTemplateHelpers
  include QuestionnaireUsageIncludeHelpers

  PATCH_URL = "http://example.org/StructureDefinition/TemplateExtractExtensionPatchRequestUrl"
  CREATE_INTRO = "These questionnaires in the IG create Observation resources from their answers."
  UPDATE_INTRO = "These questionnaires in the IG update existing Patient resources from their answers."
  WHOLE_FORM = "    - Its answers come from the whole form"
  HEIGHT_HEADING = "  - **Extraction template height**: creates a new Observation with code #{LOINC}|8302-2 " \
                   "from the answers".freeze
  PATCH_BLOCK = "- **Vitals form**\n  - **Extraction template name-patch**: updates an existing Patient with a " \
                "FHIRPath Patch\n#{WHOLE_FORM}".freeze

  CATEGORY = "http://example.org/CodeSystem/category"
  CATEGORY_URL = "http://example.org/StructureDefinition/category-"

  def template(ref, patch_url: nil)
    parts = [{ "url" => "template", "valueReference" => { "reference" => ref } },
             ({ "url" => PATCH_URL, "valueString" => patch_url } if patch_url)].compact
    { "url" => "#{SDC}templateExtract", "extension" => parts }
  end

  def observation(id, *codes)
    { "resourceType" => "Observation", "id" => id, "status" => "final",
      "code" => { "coding" => codes.map { |code| { "system" => LOINC, "code" => code } } } }
  end

  def name_patch(path = "Patient.name")
    operation = [{ "name" => "type", "valueCode" => "add" }, ({ "name" => "path", "valueString" => path } if path),
                 { "name" => "name", "valueString" => "name" }].compact
    { "resourceType" => "Parameters", "id" => "name-patch", "parameter" => [{ "name" => "operation",
                                                                              "part" => operation }] }
  end

  def template_form(root, items, contained)
    form(items, contexts: root, title: "Vitals form", url: "http://example.org/Questionnaire/vitals",
                contained:)
  end

  def weight_item(ref = "#weight")
    { "linkId" => "weight", "text" => "Body weight", "type" => "decimal", "extension" => [template(ref)] }
  end

  def create_form(item_ref = "#weight")
    template_form([template("#height")], [weight_item(item_ref)], [observation("height", "8302-2"),
                                                                   observation("weight")])
  end

  def create_group(url = HEIGHT_URL)
    obs_group(url, tests: []).tap { |group| group.add_test(id: "obs_create", file_name: "c.rb", kind: "create") }
  end

  def patient_group(*tests)
    group("Patient", tests: []).tap do |patient|
      tests.each { |id, kind, details| patient.add_test(id:, file_name: "#{id}.rb", kind:, **details.to_h) }
    end
  end

  def patch_entry(patient, patch = name_patch, request_url: "'Patient/' + %patient.id")
    describe(ig(template_form([template("#name-patch", patch_url: request_url)], [], [patch])), patient)
      .fetch(patient)
  end

  def templates(*parts) = { "url" => "#{SDC}templateExtract", "extension" => parts }

  def concept(code) = { "coding" => [{ "system" => CATEGORY, "code" => code }] }

  # A profile of the type fixing category to the code.
  def category_profile(type, code)
    element = { "id" => "#{type}.category", "path" => "#{type}.category", "patternCodeableConcept" => concept(code) }
    FHIR::StructureDefinition.new("resourceType" => "StructureDefinition", "url" => "#{CATEGORY_URL}#{code}",
                                  "type" => type, "snapshot" => { "element" => [element] })
  end

  def category_group(type, code)
    GroupMetadata.new(resource: type, profile_url: "#{CATEGORY_URL}#{code}", profile_name: "#{type} #{code}",
                      title: "#{type} #{code}", searches: [], mandatory_elements: [],
                      must_supports: { extensions: [], slices: [], elements: [] }).tap do |group|
      group.add_test(id: "create_#{code}", file_name: "c.rb", kind: "create")
    end
  end

  # The groups of the type whose profiles fix category one and two that a root template creating the type with
  # this category is described in.
  def category_groups(type, category)
    groups = %w[one two].map { |code| category_group(type, code) }
    form = template_form([template("#new")], [], [{ "resourceType" => type, "id" => "new", "category" => category }])
    resources = ig(form).tap { |ig| %w[one two].each { |code| ig.add(category_profile(type, code)) } }
    describe(resources, *groups).keys.map(&:profile_url)
  end

  def skipped(line) = "Questionnaire usage tracing: skipping Vitals form templateExtract #{line}\n"

  # Root extensions in reverse source order: a template, a launch context, then a query with an _include.
  def meds_form_with_all_sources
    root = [template("#mr"), launch("request", "MedicationRequest"), *meds_query]
    items = [*med_items, item("status", "Status", "%request.status")]
    form(items, contexts: root, title: "Meds form", url: "http://example.org/Questionnaire/meds",
                contained: [{ "resourceType" => "MedicationRequest", "id" => "mr", "status" => "draft",
                              "intent" => "order" }])
  end
end
