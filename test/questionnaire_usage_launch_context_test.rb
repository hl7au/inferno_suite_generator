# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  class QuestionnaireUsageLaunchContextTest < Minitest::Test
    GroupMetadata = InfernoSuiteGenerator::Generator::GroupMetadata
    IGResources = InfernoSuiteGenerator::Generator::IGResources

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
    MARITAL_NOT_CHECKED = "- **Demo form**\n  - **maritalStatus**: Marital status"

    def section(*parts) = "#{[HEADER, *parts].join("\n\n")}\n"

    def launch(name, *types, key: "valueCoding")
      name_value = key == "valueCoding" ? { "code" => name } : name
      { "url" => "#{SDC}launchContext",
        "extension" => [{ "url" => "name", key => name_value }] + types.map do |type|
                                                                    { "url" => "type", "valueCode" => type }
                                                                  end }
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

    def stub_ig(*hashes)
      IGResources.new.tap do |resources|
        resources.define_singleton_method(:get_resources_by_type) { |type| type == "Questionnaire" ? hashes : [] }
      end
    end

    def group(resource = "Patient", tests: %w[read must_support], must_support: ["name.family"], profile_name: nil)
      GroupMetadata.new(
        resource:, profile_name: profile_name || "#{resource} Profile", title: "#{resource} Tests", searches: [],
        must_supports: { extensions: [], slices: [], elements: must_support.map { |path| { path: } } },
        mandatory_elements: ["#{resource}.identifier"]
      ).tap do |metadata|
        tests.each { |kind| metadata.add_test(id: "#{resource.downcase}_#{kind}", file_name: "#{kind}.rb", kind:) }
      end
    end

    def describe(resources, *groups)
      result = nil
      @log = capture_io { result = QuestionnaireUsage.descriptions(ig_resources: resources, groups:) }.first
      result
    end

    def test_launch_context_goes_to_read_and_must_support_tests
      patient = group
      result = describe(ig(form), patient)

      assert_equal({ patient => {
                     "patient_read" => section(READ_INTRO, PATIENT_SOURCE),
                     "patient_must_support" => section(MS_INTRO, "- **Demo form**\n  - **name.family**: Family name"),
                     group: section(SUMMARY_INTRO, "- **Demo form**: see the read and Must Support tests",
                                    NOT_CHECKED, MARITAL_NOT_CHECKED)
                   } }, result)
    end

    def test_checked_by_any_fitting_group_but_must_support_by_own_profile
      first = group(must_support: %w[maritalStatus])
      second = group(must_support: [])
      result = describe(ig(form(default_items.drop(1))), first, second)
      read = section(READ_INTRO, PATIENT_SOURCE.lines.values_at(0, 1, 3).join.delete_suffix(" (not checked)"))

      assert_equal({ "patient_read" => read,
                     "patient_must_support" => section(MS_INTRO,
                                                       "- **Demo form**\n  - **maritalStatus**: Marital status"),
                     group: section(SUMMARY_INTRO, "- **Demo form**: see the read and Must Support tests") },
                   result[first])
      assert_equal({ "patient_read" => read, group: section(SUMMARY_INTRO, "- **Demo form**: see the read test") },
                   result[second])
    end

    def test_mandatory_id_choice_and_sliced_elements_count_as_checked
      items = [item("a", "A", "%patient.identifier", "%patient.id", "%patient.deceasedBoolean",
                    "%patient.name.given", "%patient.multipleBirthInteger", "%patient.birthDate")]
      read = describe(ig(form(items)), group(must_support: %w[deceased[x] name:official.given]))
             .values.first["patient_read"]

      assert_includes read, "reads identifier, id, deceasedBoolean, name.given, multipleBirthInteger (not checked), " \
                            "birthDate (not checked)\n"
    end

    def test_group_without_read_test_reports_not_tested
      patient = group(tests: %w[validation])
      result = describe(ig(form), patient)

      assert_equal({ patient => { group: section(SUMMARY_INTRO, "- **Demo form**: no test in this group makes its requests",
                                                 NOT_TESTED, PATIENT_SOURCE, NOT_CHECKED, MARITAL_NOT_CHECKED) } },
                   result)
    end

    def test_unused_sources_and_groups_appear_nowhere
      patient = group
      practitioner = group("Practitioner")
      observation = group("Observation")
      result = describe(ig(form(contexts: [launch("patient", "Patient"), launch("user", "Practitioner")])),
                        patient, practitioner, observation)

      assert_equal [patient], result.keys
      refute_includes result[patient].values.join, "user"
      assert_empty describe(ig, patient)
    end

    def test_where_resource_type_counts_only_for_that_type
      role = group("PractitionerRole", tests: %w[read])
      practitioner = group("Practitioner", tests: %w[read])
      items = [item("role", "Role", "%user.where(resourceType = 'PractitionerRole').code.text"),
               item("name", "Name", "%user.name.text")]
      result = describe(ig(form(items, contexts: [launch("user", "Practitioner", "PractitionerRole")])),
                        role, practitioner)

      assert_includes result[role]["practitionerrole_read"],
                      "    - **Role**: pre-fills the answer; reads code.text (not checked)\n    - **Name**"
      refute_includes result[practitioner]["practitioner_read"], "Role"
      assert_includes result[practitioner]["practitioner_read"], "    - **Name**: pre-fills the answer; reads name.text"
    end

    def test_source_with_no_group_is_logged
      describe(ig(form([item("a", "A", "%user.name")],
                       contexts: [launch("user", "Practitioner"), launch("patient", "Patient")])), group)

      assert_equal "Questionnaire usage tracing: untraced Demo form launch context user: no group for Practitioner\n",
                   @log
    end

    def test_item_lines_and_must_support_labels_are_capped
      items = (1..27).map { |index| item("q#{index}", "Item #{index}", "%patient.name.family") }
      result = describe(ig(form(items)), group)
      read = result.values.first["patient_read"]

      assert_includes read, "    - **Item 25**: pre-fills the answer; reads name.family\n    - and 2 more items\n"
      refute_includes read, "Item 26"
      assert_includes result.values.first["patient_must_support"],
                      "  - **name.family**: #{(1..10).map { |index| "Item #{index}" }.join(", ")}, and 17 more\n"
    end

    def test_forms_without_url_are_named_by_id_and_kept_apart
      first = form(url: nil, title: nil, id: "first-form")
      second = form(url: nil, title: nil, id: "second-form")
      summary = describe(ig(first, second, form(url: nil, title: nil, id: nil)), group).values.first[:group]

      assert_includes summary, "- **first-form**: see the read and Must Support tests\n" \
                               "- **second-form**: see the read and Must Support tests\n" \
                               "- **Untitled questionnaire**: see the read and Must Support tests\n"
    end

    def test_forms_with_the_same_title_show_their_versions
      forms = [form(version: "1.0.0"), form(version: "2.0.0"), form(url: "http://example.org/other")]
      summary = describe(ig(*forms, form(version: "1.0.0")), group).values.first[:group]

      assert_includes summary, "- **Demo form, version 1.0.0**: see the read and Must Support tests\n" \
                               "- **Demo form, version 2.0.0**: see the read and Must Support tests\n" \
                               "- **Demo form**: see the read and Must Support tests\n\n"
    end

    def test_item_labels_are_escaped_and_uses_merged_per_item
      items = [item("odd", "  Patient's *first*\n name_[x] `code` ", "%patient.name.family"),
               item("dup", nil, "%patient.name.family", expression("%patient.name.family", "enableWhenExpression"),
                    "%patient.name.family", "%patient.exists()")]
      read = describe(ig(form(items, extension: [launch("patient", "Patient"),
                                                 expression("%patient.name.given", "itemPopulationContext")])),
                      group).values.first["patient_read"]

      assert_includes read, "    - **The whole form**: sets the population context; reads name.given (not checked)\n    " \
                            "- **Patient's \\*first\\* name\\_\\[x\\] \\`code\\`**: pre-fills the answer; reads " \
                            "name.family\n    - **dup**: pre-fills the answer, shows or hides the item; reads name.family\n"
    end

    def test_old_sdc_launch_context_name_and_item_without_paths
      items = [item("seen", "Seen", "%patient.exists()")]
      read = describe(ig(form(items, contexts: [launch("patient", "Patient", key: "valueId")])),
                      group).values.first["patient_read"]

      assert_includes read, "  - **Launch context patient**: the Patient the form is opened for\n    " \
                            "- **Seen**: pre-fills the answer\n"
    end

    def test_groups_without_recorded_tests_raise
      error = assert_raises(RuntimeError) { describe(ig(form), group(tests: [])) }

      assert_equal "Questionnaire usage tracing must run after the test generators: no group has a recorded test.",
                   error.message
      assert_empty describe(ig(form))
    end

    def test_malformed_shapes_are_treated_as_absent
      patient = group
      nameless = { "url" => "#{SDC}launchContext", "extension" => [{ "url" => "type", "valueCode" => "Patient" }] }
      malformed = [form(url: "a", item: { "linkId" => "x" }, extension: { "url" => "x" }, contained: "x"),
                   form([{ "linkId" => "x", "extension" => { "url" => "y" }, "item" => "z" }],
                        url: "b", contexts: [nameless]),
                   form([item("bad", "Bad", "%patient.name.(", ""), *default_items], text: 5, contained: "x")]
      result = describe(stub_ig(*malformed), patient)

      assert_equal section(READ_INTRO, PATIENT_SOURCE), result[patient]["patient_read"]
      assert_equal "Questionnaire usage tracing: skipping FHIRPath \"%patient.name.(\": " \
                   "Failed to parse \"%patient.name.(\"\n", @log
    end

    def test_repeated_runs_give_identical_output
      resources = ig(form)
      groups = [group, group(must_support: ["maritalStatus"])]

      assert_equal describe(resources, *groups), describe(resources, *groups)
    end
  end
end
