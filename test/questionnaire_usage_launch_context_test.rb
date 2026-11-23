# frozen_string_literal: true

require_relative "questionnaire_usage_helpers"

module InfernoSuiteGenerator
  class QuestionnaireUsageLaunchContextTest < Minitest::Test
    include QuestionnaireUsageHelpers

    def test_launch_context_goes_to_read_and_must_support_tests
      patient = group

      assert_equal({ patient => {
                     "patient_read" => section(READ_INTRO, PATIENT_SOURCE),
                     "patient_must_support" => section(MS_INTRO, "- **Demo form**\n  - **name.family**: Family name"),
                     group: section(SUMMARY_INTRO, "- **Demo form**: #{BOTH_TESTS}", NOT_CHECKED, MARITAL_NOT_CHECKED)
                   } }, describe(ig(form), patient))
    end

    def test_checked_by_any_fitting_group_but_must_support_by_own_profile
      first = group(must_support: %w[maritalStatus])
      second = group(must_support: [])
      result = describe(ig(form(default_items.drop(1))), first, second)
      read = section(READ_INTRO, MARITAL_SOURCE)

      assert_equal({ "patient_read" => read, "patient_must_support" => section(MS_INTRO, MARITAL_NOT_CHECKED),
                     group: section(SUMMARY_INTRO, "- **Demo form**: #{BOTH_TESTS}") }, result[first])
      assert_equal({ "patient_read" => read, group: section(SUMMARY_INTRO, "- **Demo form**: see the read test") },
                   result[second])
    end

    def test_mandatory_id_choice_and_sliced_elements_count_as_checked
      items = [item("a", "A", "%patient.identifier", "%patient.id", "%patient.deceasedBoolean",
                    "%patient.name.given", "%patient.multipleBirthInteger", "%patient.birthDate")]
      read = patient_entry(form(items), patient: group(must_support: %w[deceased[x] name:official.given]))

      assert_includes read["patient_read"], "reads identifier, id, deceasedBoolean, name.given, " \
                                            "multipleBirthInteger (not checked), birthDate (not checked)\n"
    end

    def test_group_without_read_test_reports_not_tested
      patient = group(tests: %w[validation])
      summary = section(SUMMARY_INTRO, "- **Demo form**: no test in this group makes its requests",
                        NOT_TESTED, PATIENT_SOURCE, NOT_CHECKED, MARITAL_NOT_CHECKED)

      assert_equal({ patient => { group: summary } }, describe(ig(form), patient))
    end

    def test_unused_sources_and_groups_appear_nowhere
      patient = group
      result = describe(ig(form(contexts: [launch("patient", "Patient"), launch("user", "Practitioner")])),
                        patient, group("Practitioner"), group("Observation"))

      assert_equal [patient], result.keys
      refute_includes result[patient].values.join, "user"
    end

    def test_ig_without_questionnaires_gives_empty_result
      assert_empty describe(ig, group)
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
      assert_equal ["    - **Name**: pre-fills the answer; reads name.text (not checked)\n"],
                   result[practitioner]["practitioner_read"].lines.grep(/^    - /)
    end

    def test_source_with_no_group_is_logged
      contexts = [launch("user", "Practitioner"), launch("patient", "Patient")]
      describe(ig(form([item("a", "A", "%user.name")], contexts:)), group)

      assert_equal "Questionnaire usage tracing: untraced Demo form launch context user: no group for Practitioner\n",
                   @log
    end

    def test_repeated_runs_give_identical_output
      resources = ig(form)
      groups = [group, group(must_support: ["maritalStatus"])]

      assert_equal describe(resources, *groups), describe(resources, *groups)
    end
  end
end
