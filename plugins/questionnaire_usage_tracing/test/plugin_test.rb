# frozen_string_literal: true

require_relative "support"

module InfernoSuitePlugins
  module QuestionnaireUsageTracing
    # Runs the plugin the way the host does and checks what it writes to each
    # group's `plugins.yml` and adds to its description.
    class PluginTest < Minitest::Test
      include PluginRunFixtures

      def test_a_traced_group_gets_its_entries_in_plugins_yml
        run_tracing

        entries = plugin_metadata(File.join(@dir, "patient"), PLUGIN_ID)["entries"]

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

        entries = plugin_metadata(File.join(@dir, "patient"), PLUGIN_ID)["entries"]

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
        refute_path_exists File.join(@dir, "patient", "plugins.yml")
      end

      def test_the_generated_group_file_is_valid_ruby_with_the_section
        path = generate_group_file(run_tracing(patient_form(text: "Date of birth (dd/mm")))

        assert RubyVM::InstructionSequence.compile_file(path)
        assert_includes File.read(path), "## Used in questionnaires"
      end
    end

    # Runs the plugin and checks which tests' descriptions each part of the
    # trace goes to.
    class PluginTestSectionsTest < Minitest::Test
      include PluginRunFixtures

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
  end
end
