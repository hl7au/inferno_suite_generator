# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Runs the tracing the way the generator does and checks what it writes to
    # each group's trace file and adds to its description.
    class GenerateTest < Minitest::Test
      include RunFixtures

      def test_a_traced_group_gets_its_entries_in_a_trace_file
        run_tracing

        entries = trace_entries(File.join(@dir, "patient"))

        assert_equal(["launch_context"], entries.map { |entry| entry["source"] })
        assert_equal ["birthDate"], entries.first["elements_read"]
        assert_equal [{ "link_id" => "dob", "text" => "Date of birth", "extension" => "initialExpression",
                        "reads" => ["birthDate"] }],
                     entries.first["used_in"]
      end

      def test_entries_name_the_tests_that_list_them
        add_test(@group, "patient_read_test", "read")
        add_test(@group, "patient_must_support_test", "must_support")
        run_tracing

        entries = trace_entries(File.join(@dir, "patient"))

        assert_equal %w[patient_read_test patient_must_support_test], entries.first["tested_by"]
      end

      def test_a_traced_group_gets_a_used_in_questionnaires_section
        descriptions = run_tracing

        texts = descriptions.for(@group)

        assert_equal 1, texts.length
        assert texts.first.start_with?("## Used in questionnaires\n")
        assert_includes texts.first, "**#{FORM_TITLE}**"
      end

      def test_a_group_no_questionnaire_uses_is_left_alone
        descriptions = run_tracing(questionnaire)

        assert_empty descriptions.for(@group)
        refute_path_exists File.join(@dir, "patient", QuestionnaireUsage::GroupTrace::FILE_NAME)
      end

      def test_the_generated_group_file_is_valid_ruby_with_the_section
        path = generate_group_file(run_tracing(patient_form(text: "Date of birth (dd/mm")))

        assert RubyVM::InstructionSequence.compile_file(path)
        assert_includes File.read(path), "## Used in questionnaires"
      end
    end

    # Runs the tracing and checks which tests' descriptions each part of the
    # trace goes to.
    class GenerateTestSectionsTest < Minitest::Test
      include RunFixtures

      ROLE = "http://example.org/StructureDefinition/role"
      LOCATION = "http://example.org/StructureDefinition/location"

      def test_the_read_and_must_support_tests_list_what_the_form_uses
        add_test(@group, "patient_read_test", "read")
        add_test(@group, "patient_must_support_test", "must_support")
        descriptions = run_tracing

        assert_includes descriptions.for_test(@group, "patient_read_test").first,
                        "  - **Launch context patient**: the Patient the form is opened for\n    " \
                        "- **Date of birth**: pre-fills the answer; reads birthDate"
        assert_includes descriptions.for_test(@group, "patient_must_support_test").first,
                        "  - **birthDate**: Date of birth"
        assert_includes descriptions.for(@group).first, "- **#{FORM_TITLE}**: see the read and Must Support tests"
      end

      def test_without_a_read_test_the_launch_context_stays_in_the_group_summary
        summary = run_tracing.for(@group).first

        assert_includes summary, "**Not tested by this group**"
        assert_includes summary, "**Launch context patient**"
      end

      def test_an_include_goes_to_the_include_test_of_the_searching_group
        role, location = include_groups
        add_test(role, "role_include_test", "include", search_names: ["practitioner"], include_targets: ["Location"])
        descriptions = run_tracing(location_form, groups: [role, location],
                                                  profiles: { ROLE => profile("PractitionerRole"),
                                                              LOCATION => profile("Location") })

        assert_includes descriptions.for_test(role, "role_include_test").first,
                        "**Query PractitionerRoleLocation**: fetches Location resources through " \
                        "_include=PractitionerRole:location"
        assert_includes descriptions.for(location).first, "see the search with _include in Role test"
      end

      def test_an_include_names_the_profiles_it_fetches_not_the_group_of_the_test
        role, location = include_groups
        add_test(role, "role_include_test", "include", search_names: ["practitioner"], include_targets: ["Location"])
        descriptions = run_tracing(location_form, groups: [role, location],
                                                  profiles: { ROLE => profile("PractitionerRole"),
                                                              LOCATION => profile("Location") })
        section = descriptions.for_test(role, "role_include_test").first

        refute_includes section, "this group's tests"
        assert_includes section, "neither Must Support nor required by any Location profile in this suite"
      end

      def test_the_generated_group_file_appends_to_the_test
        add_test(@group, "patient_read_test", "read")
        path = generate_group_file(run_tracing)

        assert RubyVM::InstructionSequence.compile_file(path)
        assert_includes File.read(path), "test from: :patient_read_test do\n        description [description, %(\n" \
                                         "## Used in questionnaires"
      end

      private

      def include_groups
        [build_group_metadata(name: "role", resource: "PractitionerRole", profile_url: ROLE, title: "Role"),
         build_group_metadata(name: "location", resource: "Location", profile_url: LOCATION, title: "Location")]
      end

      def location_form
        query = "PractitionerRole?practitioner={{%user.id}}&_include=PractitionerRole:location:Location"
        questionnaire(
          extension: [query_variable("PractitionerRoleLocation", query)],
          item: [item("location", "Location",
                      expression("initialExpression",
                                 "%PractitionerRoleLocation.entry.resource.ofType(Location).first().name"))]
        )
      end
    end

    # Runs the tracing over an `_include` that links to two Observation groups,
    # of which only the last marks `status` Must Support.
    class GenerateSharedIncludeTest < Minitest::Test
      include RunFixtures

      BASE = "http://example.org/StructureDefinition/base"
      UNCHECKING = "http://example.org/StructureDefinition/obs-unchecking"
      CHECKING = "http://example.org/StructureDefinition/obs-checking"

      def test_a_shared_include_counts_an_element_as_checked_when_any_of_its_groups_checks_it
        section = trace_shared_include { |descriptions, base, _checking| descriptions.for_test(base, "base_include") }

        assert_includes section.first, "**Status**: pre-fills the answer; reads status\n"
        assert_includes section.first, "**Note**: pre-fills the answer; reads note (not checked)"
      end

      def test_the_must_support_test_and_the_trace_files_agree_with_a_shared_include
        section = trace_shared_include do |descriptions, _base, checking|
          descriptions.for_test(checking, "checking_must_support")
        end

        assert_includes section.first, "**status**: Status"
        assert_equal [["base_include"]], tested_by("obs_unchecking")
        assert_equal [%w[base_include checking_must_support]], tested_by("obs_checking")
      end

      def test_the_group_summary_agrees_with_the_include_test_on_a_shared_include
        summaries = trace_shared_include do |descriptions, _base, checking, unchecking|
          [unchecking, checking].map { |group| descriptions.for(group).join }
        end

        summaries.each do |summary|
          refute_includes summary, "**status**: Status"
          assert_includes summary, "**note**: Note"
        end
      end

      private

      def tested_by(directory)
        trace_entries(File.join(@dir, directory)).map { |entry| entry["tested_by"] }
      end

      # Traces an `_include` that links to two Observation groups and returns
      # what the block reads from the descriptions.
      def trace_shared_include
        base, unchecking, checking = shared_include_groups
        add_test(base, "base_include", "include", search_names: ["patient"], include_targets: ["Observation"])
        add_test(checking, "checking_must_support", "must_support")
        descriptions = run_tracing(shared_include_form, groups: [base, unchecking, checking],
                                                        profiles: { BASE => profile("MedicationRequest"),
                                                                    UNCHECKING => profile("Observation"),
                                                                    CHECKING => profile("Observation") })
        with_config_keeper { yield descriptions, base, checking, unchecking }
      end

      # Only the last Observation group marks `status` Must Support.
      def shared_include_groups
        [build_group_metadata(name: "base", resource: "MedicationRequest", profile_url: BASE, title: "Base"),
         build_group_metadata(name: "obs_unchecking", resource: "Observation", profile_url: UNCHECKING,
                              must_supports: { elements: [] }),
         build_group_metadata(name: "obs_checking", resource: "Observation", profile_url: CHECKING,
                              must_supports: { elements: [{ path: "status" }] })]
      end

      def shared_include_form
        query = "MedicationRequest?patient={{%patient.id}}&_include=MedicationRequest:reason:Observation"
        reading = ->(path) { expression("initialExpression", "%Q.entry.resource.ofType(Observation).first().#{path}") }
        questionnaire(extension: [query_variable("Q", query)],
                      item: [item("status", "Status", reading.call("status")),
                             item("note", "Note", reading.call("note"))])
      end
    end
  end
end
