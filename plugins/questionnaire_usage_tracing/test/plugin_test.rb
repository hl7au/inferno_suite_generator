# frozen_string_literal: true

require_relative "support"
require "tmpdir"
require "inferno_suite_generator/plugins/testing"

module InfernoSuitePlugins
  module QuestionnaireUsageTracing
    # Runs the plugin the way the host does and checks what it writes to each
    # group's `plugins.yml` and adds to its description.
    class PluginTest < Minitest::Test
      include TracerFixtures
      include InfernoSuiteGenerator::Plugins::Testing

      PLUGIN_ROOT = File.expand_path("..", __dir__)
      PLUGIN_ID = "questionnaire_usage_tracing"

      def setup
        @dir = Dir.mktmpdir
        @group = build_group_metadata(resource: "Patient", profile_url: AU_CORE_PATIENT)
      end

      def teardown
        FileUtils.remove_entry(@dir)
      end

      def test_a_traced_group_gets_its_entries_in_plugins_yml
        run_tracing

        entries = plugin_metadata(File.join(@dir, "patient"), PLUGIN_ID)["entries"]

        assert_equal(["launch_context"], entries.map { |entry| entry["source"] })
        assert_equal ["birthDate"], entries.first["elements_read"]
        assert_equal [{ "link_id" => "dob", "text" => "Date of birth", "extension" => "initialExpression",
                        "reads" => ["birthDate"] }],
                     entries.first["used_in"]
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
        descriptions = run_tracing(patient_form(text: "Date of birth (dd/mm"))
        with_config_keeper do
          InfernoSuiteGenerator::Generator::GroupGenerator.generate(build_ig_metadata(groups: [@group]), @dir,
                                                                    descriptions)
        end
        path = File.join(@dir, "patient_group.rb")

        assert RubyVM::InstructionSequence.compile_file(path)
        assert_includes File.read(path), "## Used in questionnaires"
      end

      private

      def run_tracing(form = patient_form)
        _groups, ig_resources = suite_for(AU_CORE_PATIENT => profile("Patient"))
        ig_resources.add(FHIR::Questionnaire.new(form))
        run_plugin(PLUGIN_ROOT, ig_metadata: build_ig_metadata(groups: [@group]), ig_resources:,
                                base_output_dir: @dir)
      end

      def patient_form(text: "Date of birth")
        questionnaire(extension: [launch_context("patient", "Patient")],
                      item: [item("dob", text, expression("initialExpression", "%patient.birthDate.toString()"))])
      end
    end
  end
end
