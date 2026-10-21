# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # Verifies `Generator::WithQuestionnaireTracing` writes the trace next to
    # each traced group's `metadata.yml`.
    class GeneratorWithQuestionnaireTracingTest < Minitest::Test
      include TracerFixtures
      include ConfigKeeperSwap

      def test_the_group_directory_gets_a_plugins_file_with_the_trace
        generate_groups

        trace = YAML.load_file(plugins_path)["questionnaire_usage_tracing"]

        assert_equal(["launch_context"], trace.map { |entry| entry["source"] })
        assert_equal ["birthDate"], trace.first["elements_read"]
        assert_equal [{ "link_id" => "dob", "text" => "Date of birth", "extension" => "initialExpression",
                        "reads" => ["birthDate"] }],
                     trace.first["used_in"]
      end

      def test_the_group_description_gets_the_section
        generate_groups

        assert_includes File.read(File.join(output_dir, "patient_group.rb")), "## Used in questionnaires"
      end

      def test_an_existing_plugins_file_keeps_its_other_keys
        FileUtils.mkdir_p(File.dirname(plugins_path))
        File.write(plugins_path, YAML.dump("other_plugin" => { "enabled" => true }))

        generate_groups

        assert_equal %w[other_plugin questionnaire_usage_tracing], YAML.load_file(plugins_path).keys
      end

      def test_a_group_without_a_trace_loses_the_key_from_an_earlier_run
        write_plugins_file("other_plugin" => { "enabled" => true }, "questionnaire_usage_tracing" => [{ "a" => 1 }])

        generate_groups(questionnaire)

        assert_equal ["other_plugin"], YAML.load_file(plugins_path).keys
      end

      def test_a_plugins_file_left_without_keys_is_removed
        write_plugins_file("questionnaire_usage_tracing" => [{ "a" => 1 }])

        generate_groups(questionnaire)

        refute_path_exists plugins_path
      end

      private

      def write_plugins_file(content)
        FileUtils.mkdir_p(File.dirname(plugins_path))
        File.write(plugins_path, YAML.dump(content))
      end

      def generate_groups(form = patient_form)
        generator = Generator::WithQuestionnaireTracing.new(nil)
        _groups, generator.ig_resources = suite_for(AU_CORE_PATIENT => profile("Patient"))
        generator.ig_resources.add(FHIR::Questionnaire.new(form))
        generator.ig_metadata = ig_metadata
        FileUtils.mkdir_p(File.join(output_dir, "patient"))
        generator.trace_questionnaires
        generator.generate_groups
      end

      def patient_form
        questionnaire(extension: [launch_context("patient", "Patient")],
                      item: [item("dob", "Date of birth",
                                  expression("initialExpression", "%patient.birthDate.toString()"))])
      end

      def ig_metadata
        Generator::IGMetadata.new.tap do |metadata|
          metadata.ig_version = "2.0.0"
          metadata.ig_module_name_prefix = "AUCore"
          metadata.ig_test_id_prefix = "au_core"
          metadata.groups = [patient_group]
        end
      end

      def patient_group
        Generator::GroupMetadata.new(resource: "Patient", profile_url: AU_CORE_PATIENT, name: "au_core_patient",
                                     title: "AU Core Patient", version: "2.0.0", reformatted_version: "200",
                                     tests: [], searches: [])
      end

      def output_dir
        File.join(@result_folder, "2.0.0")
      end

      def plugins_path
        File.join(output_dir, "patient", "plugins.yml")
      end
    end
  end
end
