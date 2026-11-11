# frozen_string_literal: true

require_relative "support"

# `QuestionnaireUsage.generate` end to end: over tests added to the groups by hand, then over the tests the real
# generators record.
module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Runs the tracing the way the generator does and checks what it adds to the descriptions, and which tests'
    # descriptions each part of the trace goes to.
    class GenerateTest < Minitest::Test
      include RunFixtures

      def test_a_traced_group_gets_a_used_in_questionnaires_section
        summary = run_tracing.summary(@group)

        assert summary.start_with?("**Used in questionnaires**\n")
        assert_equal 1, summary.scan("**Used in questionnaires**").size
        assert_includes summary, "**#{FORM_TITLE}**"
      end

      def test_a_group_no_questionnaire_uses_is_left_alone
        written = run_tracing(questionnaire)

        assert_empty written.summary(@group)
        assert_empty written.tested_by
      end

      def test_the_generated_group_file_is_valid_ruby_with_the_section
        path = generate_group_file(patient_form(text: "Date of birth (dd/mm"))

        assert RubyVM::InstructionSequence.compile_file(path)
        assert_includes File.read(path), "**Used in questionnaires**"
      end

      def test_the_read_and_must_support_tests_list_what_the_form_uses
        with_tests(@group, "patient", read: {}, must_support: {})
        written = run_tracing

        assert_equal %w[patient_read patient_must_support], written.tested_by
        assert_includes written.section("patient_read"),
                        "  - **Launch context patient**: the Patient the form is opened for\n    " \
                        "- **Date of birth**: pre-fills the answer; reads birthDate"
        assert_includes written.section("patient_must_support"), "  - **birthDate**: Date of birth"
        assert_includes written.summary(@group), "- **#{FORM_TITLE}**: see the read and Must Support tests"
      end

      def test_without_a_read_test_the_launch_context_stays_in_the_group_summary
        summary = run_tracing.summary(@group)

        assert_includes summary, "**Not tested by this group**"
        assert_includes summary, "**Launch context patient**"
      end

      # The include test lists entries of the Location groups, so it names their profiles, not its own group.
      def test_an_include_goes_to_the_include_test_of_the_searching_group
        role = build_group_metadata(name: "role", resource: "PractitionerRole", profile_url: ROLE, title: "Role")
        location = build_group_metadata(name: "location", resource: "Location", profile_url: LOCATION)
        with_tests(role, "role", include: { search_names: ["practitioner"], include_targets: ["Location"] })
        written = run_tracing(location_form, groups: [role, location], profiles: role_profiles)
        section = written.section("role_include")

        assert_includes section, "**Query PractitionerRoleLocation**: fetches Location resources through " \
                                 "_include=PractitionerRole:location"
        refute_includes section, "this group's tests"
        assert_includes section, "neither Must Support nor required by any Location profile in this suite"
        assert_includes written.summary(location), "see the search with _include in Role test"
      end
    end

    # Runs the tracing over an `_include` that links to two Observation groups,
    # of which only the last marks `status` Must Support.
    class GenerateSharedIncludeTest < Minitest::Test
      include RunFixtures

      BASE = "http://example.org/StructureDefinition/base"

      def setup
        super
        base = build_group_metadata(name: "base", resource: "MedicationRequest", profile_url: BASE, title: "Base")
        with_tests(base, "base", include: { search_names: ["patient"], include_targets: ["Observation"] })
        @unchecking = observation_group("unchecking", UNCHECKING, elements: [])
        @checking = observation_group("checking", CHECKING, elements: [{ path: "status" }])
        @written = run_tracing(shared_include_form, groups: [base, @unchecking, @checking],
                                                    profiles: { BASE => profile("MedicationRequest"),
                                                                UNCHECKING => profile("Observation"),
                                                                CHECKING => profile("Observation") })
      end

      def test_a_shared_include_counts_an_element_as_checked_when_any_of_its_groups_checks_it
        section = @written.section("base_include")

        assert_includes section, "**Status**: pre-fills the answer; reads status\n"
        assert_includes section, "**Note**: pre-fills the answer; reads note (not checked)"
      end

      def test_the_must_support_test_of_the_group_that_checks_an_element_lists_a_shared_include
        assert_includes @written.section("checking_must_support"), "**status**: Status"
        assert_equal %w[base_include checking_must_support], @written.tested_by
      end

      def test_the_group_summary_agrees_with_the_include_test_on_a_shared_include
        [@unchecking, @checking].each do |group|
          refute_includes @written.summary(group), "**status**: Status"
          assert_includes @written.summary(group), "**note**: Note"
        end
      end

      private

      def shared_include_form
        query = "MedicationRequest?patient={{%patient.id}}&_include=MedicationRequest:reason:Observation"
        reading = ->(path) { expression("initialExpression", "%Q.entry.resource.ofType(Observation).first().#{path}") }
        questionnaire(extension: [query_variable("Q", query)],
                      item: [item("status", "Status", reading.call("status")),
                             item("note", "Note", reading.call("note"))])
      end
    end

    # A suite of Patient, PractitionerRole, Location and Encounter groups with
    # the metadata the real generators need, and a form that reads each of them.
    module WiringFixtures
      include FormFixtures

      ENCOUNTER = "http://example.org/StructureDefinition/encounter"
      PATIENT_INTERACTIONS = %w[read create update patch].map { |code| { code:, expectation: "SHALL" } }.freeze

      def wiring_config
        { "configs" => {
          "generic" => { "questionnaire_usage_tracing" => true },
          "profiles" => { ROLE => { "extra_searches" => [
            { "type" => "include", "names" => ["practitioner"], "param" => "location",
              "target_resource" => "Location", "paths" => ["location"] }
          ] } }
        } }
      end

      def wiring_resources
        _groups, ig_resources = suite_for(role_profiles.merge(patient_profile, ENCOUNTER => profile("Encounter")))
        ig_resources.add(FHIR::Questionnaire.new(wiring_form))
        ig_resources
      end

      def wiring_groups
        [patient_group, role_group, location_group, encounter_group]
      end

      private

      def patient_group
        build_group_metadata(
          name: "example_patient", resource: "Patient", profile_url: AU_CORE_PATIENT,
          interactions: PATIENT_INTERACTIONS, must_supports: must_supports(elements: [{ path: "birthDate" }]),
          searches: [{ names: ["family"], expectation: "SHALL" }],
          search_definitions: { family: search_definition("name.family", "string") }
        )
      end

      def role_group
        build_group_metadata(
          name: "example_role", class_name: "ExampleRoleSequence", resource: "PractitionerRole", profile_url: ROLE,
          title: "Role", must_supports:, searches: [{ names: ["practitioner"], expectation: "SHALL" }],
          search_definitions: { practitioner: search_definition("practitioner", "Reference") }
        )
      end

      def location_group
        build_group_metadata(name: "example_location", class_name: "ExampleLocationSequence", resource: "Location",
                             profile_url: LOCATION, title: "Location", must_supports:)
      end

      def encounter_group
        build_group_metadata(
          name: "example_encounter", class_name: "ExampleEncounterSequence", resource: "Encounter",
          profile_url: ENCOUNTER, title: "Encounter", must_supports:,
          interactions: [{ code: "update", expectation: "SHALL" }], update_create: true,
          update_create_expectation: "SHOULD"
        )
      end

      def must_supports(elements: [])
        { elements:, slices: [], extensions: [] }
      end

      def search_definition(path, type)
        { paths: [path], full_paths: [path], type:, comparators: {} }
      end

      def wiring_form
        patch_url = "'Patient/' + %id"
        questionnaire(
          contained: templates,
          extension: [launch_context("patient", "Patient"), query_variable("Searched", "Patient?family={{%f}}"),
                      query_variable("Roles", role_query), template_extract("#new-patient"),
                      template_extract("#patch-patient", patch_url:), template_extract("#patch-encounter", patch_url:)],
          item: [reading_item("dob", "%patient.birthDate"),
                 reading_item("found", "%Searched.entry.resource.first().name"),
                 reading_item("loc", "%Roles.entry.resource.ofType(Location).first().name")]
        )
      end

      def templates
        [{ "resourceType" => "Patient", "id" => "new-patient" },
         patch_template("patch-patient", path: "Patient.name"),
         patch_template("patch-encounter", path: "Encounter.status")]
      end

      def reading_item(link_id, fhirpath)
        item(link_id, link_id, expression("initialExpression", fhirpath))
      end
    end

    # Runs the real generators in `Generator#generate` order. Other tests add tests to groups by hand, so only this
    # one proves the tracing finds what the generators record.
    class GeneratorWiringTest < Minitest::Test
      include RunFixtures
      include WiringFixtures

      READ = "example_v100_patient_read_test"

      def test_a_launch_context_goes_to_the_generated_read_and_must_support_tests
        assert_equal [READ], tested_by("**Launch context patient**")
        assert_includes written.section("example_v100_patient_must_support_test"), "**birthDate**: dob"
      end

      def test_a_search_goes_to_the_generated_search_test
        assert_equal ["example_v100_patient_family_search_test"], tested_by("**Query Searched**")
      end

      def test_an_include_goes_to_the_generated_include_test_of_the_searching_group
        assert_equal ["example_v100_practitioner_role_practitioner_include_practitioner_search_test"],
                     tested_by("**Query Roles**: fetches Location resources")
      end

      def test_a_template_goes_to_the_generated_create_test
        assert_equal ["example_v100_patient_create_test"], tested_by("**Extraction template new-patient**")
      end

      def test_a_fhirpath_patch_template_goes_to_the_generated_patch_test
        assert_equal ["example_v100_patient_fhirpath_json_patch_test"],
                     tested_by("**Extraction template patch-patient**")
      end

      def test_a_fhirpath_patch_template_without_a_patch_test_goes_to_the_plain_update_test
        assert_equal ["example_v100_encounter_update_update_test"], tested_by("**Extraction template patch-encounter**")
      end

      def test_the_group_file_lists_the_section_in_the_generated_read_test
        with_config_keeper(wiring_config) { generator.generate }
        path = File.join(@dir, "patient_group.rb")

        assert RubyVM::InstructionSequence.compile_file(path)
        assert_includes File.read(path), "test from: :#{READ} do\n        description [description, %(\n" \
                                         "**Used in questionnaires**"
      end

      def test_tracing_before_the_test_generators_raises
        with_config_keeper(wiring_config) do
          error = assert_raises(RuntimeError) { generator.generate_questionnaire_usage }

          assert_includes error.message, "after the test generators"
        end
      end

      private

      # The ids of the generated tests whose section lists the source with this heading.
      def tested_by(heading)
        written.sections.select { |_id, section| section.include?(heading) }.keys
      end

      # What the generators wrote for the suite's groups.
      def written
        @written ||= with_config_keeper(wiring_config) do
          generated = generator.tap(&:generate)
          written_in(generated.group_descriptions, generated.ig_metadata.groups)
        end
      end

      # A generator over the suite that skips loading the IG and writing the suite.
      def generator
        dir = @dir
        Generator.new(nil).tap do |generator|
          generator.ig_resources = wiring_resources
          generator.ig_metadata = build_ig_metadata(groups: wiring_groups)
          generator.define_singleton_method(:base_output_dir) { dir }
          %i[load_ig_package extract_metadata extract_demodata generate_suites use_tests].each do |step|
            generator.define_singleton_method(step) { nil }
          end
        end
      end
    end
  end
end
