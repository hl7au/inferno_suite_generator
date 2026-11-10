# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # A suite of Patient, PractitionerRole, Location and Encounter groups with
    # the metadata the real generators need, and a form that reads each of them.
    module WiringFixtures
      include FormFixtures

      ROLE = "http://example.org/StructureDefinition/role"
      LOCATION = "http://example.org/StructureDefinition/location"
      ENCOUNTER = "http://example.org/StructureDefinition/encounter"
      ROLES_QUERY = "PractitionerRole?practitioner={{%user.id}}&_include=PractitionerRole:location:Location"
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
        _groups, ig_resources = suite_for(ROLE => profile("PractitionerRole"), LOCATION => profile("Location"),
                                          AU_CORE_PATIENT => profile("Patient"), ENCOUNTER => profile("Encounter"))
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
        questionnaire(
          contained: templates,
          extension: [launch_context("patient", "Patient"), query_variable("Searched", "Patient?family={{%f}}"),
                      query_variable("Roles", ROLES_QUERY), template("#new-patient"),
                      template("#patch-patient", patch_url), template("#patch-encounter", patch_url)],
          item: [reading_item("dob", "%patient.birthDate"),
                 reading_item("found", "%Searched.entry.resource.first().name"),
                 reading_item("loc", "%Roles.entry.resource.ofType(Location).first().name")]
        )
      end

      def templates
        [{ "resourceType" => "Patient", "id" => "new-patient" },
         patch_parameters("patch-patient", "Patient.name"),
         patch_parameters("patch-encounter", "Encounter.status")]
      end

      def reading_item(link_id, fhirpath)
        item(link_id, link_id, expression("initialExpression", fhirpath))
      end

      def patch_parameters(id, path)
        { "resourceType" => "Parameters", "id" => id,
          "parameter" => [{ "name" => "operation", "part" => [{ "name" => "path", "valueString" => path }] }] }
      end

      def template(reference, *parts)
        { "url" => "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-templateExtract",
          "extension" => [{ "url" => "template", "valueReference" => { "reference" => reference } }, *parts] }
      end

      def patch_url
        { "url" => "https://example.org/TemplateExtractExtensionPatchRequestUrl", "valueString" => "'Patient/' + %id" }
      end
    end

    # Runs the real generators in the order `Generator#generate` runs them, and
    # checks that the tracing finds the tests they wrote. Other tests add tests
    # to a group by hand, so nothing else proves the generators and `Delivery`
    # agree on what they recorded.
    class GeneratorWiringTest < Minitest::Test
      include RunFixtures
      include WiringFixtures

      READ = "example_v100_patient_read_test"

      def test_a_launch_context_goes_to_the_generated_read_and_must_support_tests
        assert_equal [READ, "example_v100_patient_must_support_test"], tested_by("patient", "launch_context", "patient")
      end

      def test_a_search_goes_to_the_generated_search_test
        assert_equal ["example_v100_patient_family_search_test"], tested_by("patient", "query", "Searched")
      end

      def test_an_include_goes_to_the_generated_include_test_of_the_searching_group
        assert_equal ["example_v100_practitioner_role_practitioner_include_practitioner_search_test"],
                     tested_by("location", "include", "Roles")
      end

      def test_a_template_goes_to_the_generated_create_test
        assert_equal ["example_v100_patient_create_test"], tested_by("patient", "template_extract", "new-patient")
      end

      def test_a_fhirpath_patch_template_goes_to_the_generated_patch_test
        assert_equal ["example_v100_patient_fhirpath_json_patch_test"],
                     tested_by("patient", "template_extract", "patch-patient")
      end

      def test_a_fhirpath_patch_template_without_a_patch_test_goes_to_the_plain_update_test
        assert_equal ["example_v100_encounter_update_update_test"],
                     tested_by("encounter", "template_extract", "patch-encounter")
      end

      def test_the_group_file_lists_the_section_in_the_generated_read_test
        with_config_keeper(wiring_config) { generator.generate }
        path = File.join(@dir, "patient_group.rb")

        assert RubyVM::InstructionSequence.compile_file(path)
        assert_includes File.read(path), "test from: :#{READ} do\n        description [description, %(\n" \
                                         "## Used in questionnaires"
      end

      def test_tracing_before_the_test_generators_raises
        with_config_keeper(wiring_config) do
          error = assert_raises(RuntimeError) { generator.generate_questionnaire_usage }

          assert_includes error.message, "after the test generators"
        end
      end

      private

      def tested_by(directory, source, name)
        with_config_keeper(wiring_config) { generator.generate }
        entry = trace_entries(File.join(@dir, directory)).find do |candidate|
          candidate.values_at("source", "name") == [source, name]
        end
        entry.fetch("tested_by")
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
