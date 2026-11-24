# frozen_string_literal: true

require_relative "questionnaire_usage_template_helpers"

module InfernoSuiteGenerator
  # templateExtract sources: create templates go to the create test, patch templates to patch, then update.
  class QuestionnaireUsageTemplateTest < Minitest::Test
    include QuestionnaireUsageTemplateHelpers

    def test_create_template_goes_to_the_create_test_with_its_codes_and_item_uses
      group = create_group
      entry = describe(obs_ig(create_form), group).fetch(group)

      assert_equal section(CREATE_INTRO, "- **Vitals form**\n#{HEIGHT_HEADING}\n#{WHOLE_FORM}\n  " \
                                         "- **Extraction template weight**: creates a new Observation from the " \
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

    def test_create_template_goes_to_the_profile_whose_fixed_category_overlaps
      assert_equal ["#{CATEGORY_URL}two"], category_groups("Observation", [concept("two")])
    end

    def test_create_template_with_a_single_category_goes_to_the_profile_whose_fixed_category_overlaps
      assert_equal ["#{CATEGORY_URL}two"], category_groups("Procedure", concept("two"))
    end

    def test_template_on_a_nested_item_is_used_by_that_item
      group = create_group
      outer = { "linkId" => "vitals", "text" => "Vitals", "type" => "group", "item" => [weight_item] }

      assert_includes describe(obs_ig(template_form([], [outer], [observation("weight")])), group)
        .dig(group, "obs_create"),
                      "  - **Extraction template weight**: creates a new Observation from the answers\n    " \
                      "- **Body weight**: its answers fill the template"
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

    def test_patch_template_never_goes_to_an_update_test_without_an_option
      entry = patch_entry(patient_group(%w[patient_update update]))

      assert_equal %i[group], entry.keys
      assert_includes entry[:group], "#{NOT_TESTED}\n\n#{PATCH_BLOCK}\n"
    end

    def test_patch_template_type_falls_back_to_the_request_url
      entry = patch_entry(patient_group(%w[patient_patch patch]), name_patch(nil))

      assert_equal section(UPDATE_INTRO, PATCH_BLOCK), entry["patient_patch"]
    end

    def test_patch_template_without_a_type_is_logged_and_skipped
      patient = patient_group(%w[patient_patch patch])
      resources = ig(template_form([template("#name-patch", patch_url: "%patient.id")], [], [name_patch("name")]))

      assert_equal({}, describe(resources, patient))
      assert_equal "Questionnaire usage tracing: skipping Vitals form templateExtract #name-patch on root: " \
                   "no resource type in its patch path or request URL\n", @log
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

      assert_includes describe(ig(meds_form_with_all_sources), mr, med_group).fetch(mr)[:group],
                      "- **Meds form**: see the #{LABEL}, read and create tests\n"
    end
  end
end
