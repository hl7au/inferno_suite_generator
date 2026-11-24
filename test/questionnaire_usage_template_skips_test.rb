# frozen_string_literal: true

require_relative "questionnaire_usage_template_helpers"

module InfernoSuiteGenerator
  # templateExtract that are skipped: each is logged once, with its form, reference and node.
  class QuestionnaireUsageTemplateSkipsTest < Minitest::Test
    include QuestionnaireUsageTemplateHelpers

    def test_template_without_a_reference_is_logged_and_skipped
      [templates, templates({ "url" => "template", "valueReference" => { "display" => "Height" } })].each do |root|
        assert_equal({}, describe(obs_ig(template_form([root], [], [observation("height")])), create_group))
        assert_equal skipped("on root: no template reference"), @log
      end
    end

    def test_contained_resource_without_id_is_not_a_template
      group = create_group
      form = template_form([template("#"), template("#height")], [],
                           [observation("height").except("id"), observation("height", "8302-2")])

      assert_equal section(CREATE_INTRO, "- **Vitals form**\n#{HEIGHT_HEADING}\n#{WHOLE_FORM}"),
                   describe(obs_ig(form), group).fetch(group)["obs_create"]
      assert_equal skipped("# on root: no contained resource #"), @log
    end

    def test_template_on_an_item_without_link_id_is_logged_with_a_fallback_label
      describe(obs_ig(template_form([], [weight_item("#missing").except("linkId")], [])), create_group)

      assert_equal skipped("#missing on an item without linkId: no contained resource #missing"), @log
    end

    def test_variable_on_an_item_without_link_id_is_logged_with_a_fallback_label
      names = item("names", "Names", variable("First", "%Second.family"), variable("Second", "%patient.name"),
                   "%First").except("linkId")
      describe(ig(form([names])), group)

      assert_equal "Questionnaire usage tracing: untraced Demo form variable First on an item without linkId: " \
                   "it uses Second, defined after it\n", @log
    end

    def test_contained_resource_without_resource_type_is_logged_and_skipped
      form = template_form([template("#bare")], [], [{ "id" => "bare" }])

      assert_equal({}, describe(stub_ig(form), create_group))
      assert_equal skipped("#bare on root: the contained resource has no resourceType"), @log
    end

    def test_patch_request_url_is_read_only_from_a_string
      url = { "url" => PATCH_URL, "valueExpression" => { "language" => "text/fhirpath",
                                                         "expression" => "'Patient/' + %patient.id" } }
      root = templates({ "url" => "template", "valueReference" => { "reference" => "#name-patch" } }, url)

      resources = ig(template_form([root], [], [name_patch(nil)]))

      assert_equal({}, describe(resources, patient_group(%w[patient_patch patch])))
      assert_equal skipped("#name-patch on root: no resource type in its patch path or request URL"), @log
    end
  end
end
