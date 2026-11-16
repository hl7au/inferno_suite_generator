# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"
require "tmpdir"

module InfernoSuiteGenerator
  # Builds a SuiteGenerator over fake IG metadata and config, so a test can render the suite template.
  module SuiteGeneratorTestHelpers
    SuiteGenerator = InfernoSuiteGenerator::Generator::SuiteGenerator
    GeneratorConfigKeeper = InfernoSuiteGenerator::Generator::GeneratorConfigKeeper

    FakeIgMetadata = Struct.new(
      :ig_test_id_prefix, :ig_module_name_prefix, :reformatted_version, :ig_title, :ig_version, :ig_id,
      :ordered_groups, keyword_init: true
    ) do
      def patch_interaction_exists?
        false
      end
    end

    FakeConfigKeeper = Struct.new(
      :validation_message_overrides, :tx_server_url, :snomed_edition, :fhirpathlab_url, :rewrite_igs,
      :ig_name, :ig_link, :default_fhir_server, :links, :outer_groups, :extra_imports, :suite_module_name,
      :fhirpathlab_serve_resources?, keyword_init: true
    )

    def setup
      @previous_config_keeper = Registry.get(:config_keeper)
    end

    def teardown
      Registry.register(:config_keeper, @previous_config_keeper)
    end

    private

    def build_generator(rules, serve_resources: true)
      Registry.register(:config_keeper, fake_config_keeper(rules, serve_resources))
      SuiteGenerator.new(fake_ig_metadata, Dir.tmpdir)
    end

    def fake_config_keeper(rules, serve_resources)
      FakeConfigKeeper.new(
        fhirpathlab_serve_resources?: serve_resources,
        validation_message_overrides: rules, tx_server_url: "http://tx.example.org", snomed_edition: "au",
        fhirpathlab_url: "https://fhirpath-lab.com/FhirPath", rewrite_igs: nil, ig_name: "Example IG",
        ig_link: "http://example.org/ig", default_fhir_server: "http://fhir.example.org", links: [],
        outer_groups: [], extra_imports: [], suite_module_name: "ExampleTestKit"
      )
    end

    def fake_ig_metadata
      FakeIgMetadata.new(
        ig_test_id_prefix: "example", ig_module_name_prefix: "Example", reformatted_version: "100",
        ig_title: "Example", ig_version: "v1.0.0", ig_id: "example.ig", ordered_groups: []
      )
    end
  end

  class SuiteGeneratorValidationMessageOverridesTest < Minitest::Test
    include SuiteGeneratorTestHelpers

    VALID_RULE = {
      "pattern" => "The value provided \\('(xml|json)'\\) was not found",
      "location" => "^Bundle\\.entry",
      "from" => ["error"],
      "to" => "warning",
      "comment" => "Known tx server issue"
    }.freeze

    def test_config_getter_defaults_to_empty_array
      assert_equal [], config_keeper_with({ "suite" => {} }).validation_message_overrides
    end

    def test_config_getter_returns_configured_rules
      config = { "suite" => { "validation_message_overrides" => [VALID_RULE] } }

      assert_equal [VALID_RULE], config_keeper_with(config).validation_message_overrides
    end

    def test_renders_rules_without_comment
      rendered = eval(build_generator([VALID_RULE]).validation_message_overrides) # rubocop:disable Security/Eval

      assert_equal [VALID_RULE.except("comment")], rendered
    end

    def test_renders_empty_array_without_rules
      assert_equal "[]", build_generator([]).validation_message_overrides
    end

    def test_raises_on_invalid_pattern
      rule = { "pattern" => "(", "to" => "info" }

      assert_raises(RegexpError) { build_generator([rule]).validation_message_overrides }
    end

    def test_raises_on_invalid_location
      rule = { "pattern" => "x", "location" => "[", "to" => "info" }

      assert_raises(RegexpError) { build_generator([rule]).validation_message_overrides }
    end

    def test_raises_on_missing_pattern
      assert_raises(ArgumentError) { build_generator([{ "to" => "info" }]).validation_message_overrides }
    end

    def test_raises_on_invalid_to
      rule = { "pattern" => "x", "to" => "fatal" }

      assert_raises(ArgumentError) { build_generator([rule]).validation_message_overrides }
    end

    def test_raises_on_missing_to
      assert_raises(ArgumentError) { build_generator([{ "pattern" => "x" }]).validation_message_overrides }
    end

    def test_raises_on_invalid_from
      rule = { "pattern" => "x", "from" => ["fatal"], "to" => "info" }

      assert_raises(ArgumentError) { build_generator([rule]).validation_message_overrides }
    end

    def test_suite_template_wires_overrides_into_validator
      output = build_generator([VALID_RULE]).output

      RubyVM::InstructionSequence.compile(output) # raises SyntaxError if the suite is not valid Ruby
      assert_includes output, "require 'inferno_suite_generator/utils/validation_message_overrides'"
      assert_includes output, "extend InfernoSuiteGenerator::ValidationMessageOverrides"
      assert_includes output, "message_overrides VALIDATION_MESSAGE_OVERRIDES"

      constant_line = output.lines.find { |line| line.include?("VALIDATION_MESSAGE_OVERRIDES = ") }
      rendered = eval(constant_line.split(" = ", 2).last) # rubocop:disable Security/Eval
      assert_equal [VALID_RULE.except("comment")], rendered
    end

    private

    def config_keeper_with(config)
      GeneratorConfigKeeper.allocate.tap { |keeper| keeper.instance_variable_set(:@config, config) }
    end
  end

  class SuiteGeneratorSessionResourceRoutesTest < Minitest::Test
    include SuiteGeneratorTestHelpers

    def test_suite_template_serves_session_resources_to_fhirpath_lab_cross_origin
      output = build_generator([]).output
      resource_path = "'/resources/:session_id/:resource_type/:resource_id'"

      RubyVM::InstructionSequence.compile(output)
      assert_includes output, "FHIRPATHLAB_SERVE_RESOURCES = true"
      assert_includes output, "InfernoSuiteGenerator::FhirpathLabCors.new("
      assert_includes output, "lab_url: FHIRPATHLAB_URL"
      assert_includes output, "suite_endpoint :get, #{resource_path}, session_resource_handler"
      assert_includes output, "suite_endpoint :options, #{resource_path}, session_resource_handler"
    end

    def test_suite_template_registers_no_resource_route_when_serving_is_disabled
      output = build_generator([], serve_resources: false).output

      RubyVM::InstructionSequence.compile(output)
      assert_includes output, "FHIRPATHLAB_SERVE_RESOURCES = false"
      refute_includes output, "suite_endpoint"
      refute_includes output, "FetchResourceEndpoint"
    end

    def test_fhirpathlab_serve_resources_is_on_unless_explicitly_false
      assert serve_resources?({})
      assert serve_resources?({ "fhirpathlab_serve_resources" => true })
      refute serve_resources?({ "fhirpathlab_serve_resources" => false })
    end

    def test_suite_template_registers_no_route_that_changes_data
      output = build_generator([]).output

      refute_includes output, "suite_endpoint :delete"
      refute_includes output, "DeleteSessionResourcesEndpoint"
    end

    private

    def serve_resources?(suite_config)
      keeper = GeneratorConfigKeeper.allocate
      keeper.instance_variable_set(:@config, { "suite" => suite_config })
      keeper.fhirpathlab_serve_resources?
    end
  end
end
