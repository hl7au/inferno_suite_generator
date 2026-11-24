# frozen_string_literal: true

require_relative "questionnaire_usage_include_helpers"

module InfernoSuiteGenerator
  # templateExtract sources: create templates go to the create test, patch templates to patch, then update.
  class QuestionnaireUsageTemplateTest < Minitest::Test
    include QuestionnaireUsageIncludeHelpers

    PATCH_URL = "http://example.org/StructureDefinition/TemplateExtractExtensionPatchRequestUrl"
    CREATE_INTRO = "These questionnaires in the IG create Observation resources from their answers."
    UPDATE_INTRO = "These questionnaires in the IG update existing Patient resources from their answers."
    WHOLE_FORM = "    - Its answers come from the whole form"
    HEIGHT_HEADING = "  - **Extraction template height**: creates a new Observation with code #{LOINC}|8302-2 " \
                     "from the answers".freeze
    PATCH_BLOCK = "- **Vitals form**\n  - **Extraction template name-patch**: updates an existing Patient with a " \
                  "FHIRPath Patch\n#{WHOLE_FORM}".freeze

    def template(ref, patch_url: nil)
      parts = [{ "url" => "template", "valueReference" => { "reference" => ref } },
               *({ "url" => PATCH_URL, "valueString" => patch_url } if patch_url)]
      { "url" => "#{SDC}templateExtract", "extension" => parts }
    end

    def observation(id, *codes)
      { "resourceType" => "Observation", "id" => id, "status" => "final",
        "code" => { "coding" => codes.map { |code| { "system" => LOINC, "code" => code } } } }
    end

    def name_patch(path = "Patient.name")
      operation = [{ "name" => "type", "valueCode" => "add" }, *({ "name" => "path", "valueString" => path } if path),
                   { "name" => "name", "valueString" => "name" }]
      { "resourceType" => "Parameters", "id" => "name-patch", "parameter" => [{ "name" => "operation",
                                                                                "part" => operation }] }
    end

    def template_form(root, items, contained)
      form(items, contexts: root, title: "Vitals form", url: "http://example.org/Questionnaire/vitals",
                  contained:)
    end

    def weight_item(ref = "#weight") = { "linkId" => "weight", "text" => "Body weight", "type" => "decimal",
                                          "extension" => [template(ref)] }

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

    def test_create_template_goes_to_the_create_test_with_its_codes_and_item_uses
      group = create_group
      entry = describe(obs_ig(create_form), group).fetch(group)

      assert_equal section(CREATE_INTRO, "- **Vitals form**\n#{HEIGHT_HEADING}\n#{WHOLE_FORM}\n" \
                                         "  - **Extraction template weight**: creates a new Observation from the " \
                                         "answers\n    - **Body weight**: its answers fill the template"),
                   entry["obs_create"]
      assert_includes entry[:group], "- **Vitals form**: see the create test\n"
      assert_empty @log
    end

    def test_create_template_goes_to_the_profile_whose_fixed_codes_overlap
      height = create_group
      weight = create_group(WEIGHT_URL)
      form = template_form([], [weight_item], [observation("weight", "29463-7")])
      result = describe(obs_ig(form, profiles: [profile(HEIGHT_URL, "8302-2"), profile(WEIGHT_URL, "29463-7")]),
                        height, weight)

      assert_equal [weight], result.keys
      assert_includes result[weight]["obs_create"], "creates a new Observation with code #{LOINC}|29463-7 from"
    end

    def test_patch_template_goes_to_the_patch_test
      patient = patient_group(["patient_update", "update", { option: "update" }], %w[patient_patch patch])

      assert_equal section(UPDATE_INTRO, PATCH_BLOCK), patch_entry(patient)["patient_patch"]
      assert_includes patch_entry(patient)[:group], "- **Vitals form**: see the patch test\n"
    end

    def test_patch_template_without_patch_test_goes_to_the_update_test
      patient = patient_group(["patient_new", "update", { option: "update_new" }],
                              ["patient_update", "update", { option: "update" }])
      entry = patch_entry(patient)

      assert_equal section(UPDATE_INTRO, PATCH_BLOCK), entry["patient_update"]
      assert_nil entry["patient_new"]
      assert_includes entry[:group], "- **Vitals form**: see the update test\n"
    end

    def test_patch_template_never_goes_to_an_update_test_that_creates
      entry = patch_entry(patient_group(["patient_new", "update", { option: "update_new" }]))

      assert_equal %i[group], entry.keys
      assert_includes entry[:group], "- **Vitals form**: no test in this group makes its requests\n"
      assert_includes entry[:group], "#{NOT_TESTED}\n\n#{PATCH_BLOCK}\n"
    end

    def test_patch_template_type_falls_back_to_the_request_url
      entry = patch_entry(patient_group(%w[patient_patch patch]), name_patch(nil))

      assert_equal section(UPDATE_INTRO, PATCH_BLOCK), entry["patient_patch"]
    end

    def test_missing_contained_resource_is_logged_and_the_rest_is_traced
      group = create_group
      entry = describe(obs_ig(create_form("#missing")), group).fetch(group)

      assert_equal section(CREATE_INTRO, "- **Vitals form**\n#{HEIGHT_HEADING}\n#{WHOLE_FORM}"), entry["obs_create"]
      assert_equal "Questionnaire usage tracing: skipping Vitals form templateExtract #missing on weight: " \
                   "no contained resource #missing\n", @log
    end

    def test_template_without_group_is_logged_with_its_context
      assert_equal({}, describe(obs_ig(create_form), patient_group(%w[patient_patch patch])))
      assert_equal "Questionnaire usage tracing: untraced Vitals form templateExtract #height on root: no group " \
                   "for Observation\nQuestionnaire usage tracing: untraced Vitals form templateExtract #weight on " \
                   "weight: no group for Observation\n", @log
    end

    def test_sources_are_queries_with_their_includes_then_launch_contexts_then_templates
      mr = mr_group
      mr.add_test(id: "mr_read", file_name: "read.rb", kind: "read")
      mr.add_test(id: "mr_create", file_name: "create.rb", kind: "create")
      mr_template = { "resourceType" => "MedicationRequest", "id" => "mr", "status" => "draft",
                      "intent" => "order" }
      root = [template("#mr"), launch("request", "MedicationRequest"), *meds_query]
      items = [*med_items, item("status", "Status", "%request.status")]
      meds = form(items, contexts: root, title: "Meds form", url: "http://example.org/Questionnaire/meds",
                         contained: [mr_template])

      assert_includes describe(ig(meds), mr, med_group).fetch(mr)[:group],
                      "- **Meds form**: see the #{LABEL}, read and create tests\n"
    end
  end
end
