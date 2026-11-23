# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"

# Small in-memory questionnaires and groups for QuestionnaireUsage.descriptions tests.
module QuestionnaireUsageHelpers
  GroupMetadata = InfernoSuiteGenerator::Generator::GroupMetadata
  IGResources = InfernoSuiteGenerator::Generator::IGResources
  QuestionnaireUsage = InfernoSuiteGenerator::QuestionnaireUsage

  SDC = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-"
  HEADER = "**Used in questionnaires**"
  READS = "A form can pre-fill an item only if the server returns the elements the item reads."
  READ_INTRO = "These questionnaires in the IG read Patient resources as this test does: by id, or as the " \
               "resource a form is opened for. #{READS} Elements marked (not checked) are neither Must Support " \
               "nor required by the profile, so this group's tests do not check them.".freeze
  MS_INTRO = "Items in these questionnaires read elements of Patient that this group's tests check. #{READS}".freeze
  SUMMARY_INTRO = "These questionnaires in the IG read or create Patient Profile resources. The tests that make " \
                  "the same requests list the form items that depend on them."
  NOT_TESTED = "**Not tested by this group**\n\nNo test in this group makes these requests or writes these " \
               "resources, so nothing checks what these forms get from them."
  NOT_CHECKED = "**Elements not checked**\n\nThe profile neither marks these elements Must Support nor requires " \
                "them, so no test checks that the server returns them."
  PATIENT_SOURCE = <<~MARKDOWN.chomp
    - **Demo form**
      - **Launch context patient**: the Patient the form is opened for
        - **Family name**: pre-fills the answer; reads name.family
        - **Marital status**: pre-fills the answer; reads maritalStatus (not checked)
  MARKDOWN
  MARITAL_SOURCE = <<~MARKDOWN.chomp
    - **Demo form**
      - **Launch context patient**: the Patient the form is opened for
        - **Marital status**: pre-fills the answer; reads maritalStatus
  MARKDOWN
  MARITAL_NOT_CHECKED = "- **Demo form**\n  - **maritalStatus**: Marital status"
  BOTH_TESTS = "see the read and Must Support tests"

  def section(*parts) = "#{[HEADER, *parts].join("\n\n")}\n"

  def launch(name, *types, key: "valueCoding")
    name_value = key == "valueCoding" ? { "code" => name } : name
    type_parts = types.map { |type| { "url" => "type", "valueCode" => type } }
    { "url" => "#{SDC}launchContext", "extension" => [{ "url" => "name", key => name_value }, *type_parts] }
  end

  def expression(text, kind = "initialExpression")
    { "url" => "#{SDC}#{kind}", "valueExpression" => { "language" => "text/fhirpath", "expression" => text } }
  end

  def item(link_id, text, *expressions)
    { "linkId" => link_id, "text" => text, "type" => "string",
      "extension" => expressions.map { |entry| entry.is_a?(Hash) ? entry : expression(entry) } }.compact
  end

  def form(items = default_items, contexts: [launch("patient", "Patient")], **fields)
    { "resourceType" => "Questionnaire", "url" => "http://example.org/Questionnaire/demo", "title" => "Demo form",
      "status" => "active", "extension" => contexts, "item" => items }.merge(fields.transform_keys(&:to_s))
  end

  def default_items
    [item("family", "Family name", "%patient.name.family"),
     item("marital", "Marital status", "%patient.maritalStatus")]
  end

  def ig(*forms)
    IGResources.new.tap { |resources| forms.each { |hash| resources.add(FHIR::Questionnaire.new(hash)) } }
  end

  # Plain Hashes cannot go through IGResources#add, so they come from a stubbed reader.
  def stub_ig(*hashes)
    IGResources.new.tap do |resources|
      resources.define_singleton_method(:get_resources_by_type) { |type| type == "Questionnaire" ? hashes : [] }
    end
  end

  def group(resource = "Patient", tests: %w[read must_support], must_support: ["name.family"])
    GroupMetadata.new(
      resource:, profile_name: "#{resource} Profile", title: "#{resource} Tests", searches: [],
      must_supports: { extensions: [], slices: [], elements: must_support.map { |path| { path: } } },
      mandatory_elements: ["#{resource}.identifier"]
    ).tap do |metadata|
      tests.each { |kind| metadata.add_test(id: "#{resource.downcase}_#{kind}", file_name: "#{kind}.rb", kind:) }
    end
  end

  # The descriptions; log lines land in @log.
  def describe(resources, *groups)
    result = nil
    out, = capture_io { result = QuestionnaireUsage.descriptions(ig_resources: resources, groups:) }
    @log = out
    result
  end

  # The one Patient group's entry for the given forms.
  def patient_entry(*forms, patient: group)
    describe(ig(*forms), patient).fetch(patient)
  end
end
