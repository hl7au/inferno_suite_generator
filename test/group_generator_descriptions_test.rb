# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"
require "tmpdir"

module InfernoSuiteGenerator
  class GroupGeneratorDescriptionsTest < Minitest::Test
    GroupGenerator = InfernoSuiteGenerator::Generator::GroupGenerator
    GroupMetadata = InfernoSuiteGenerator::Generator::GroupMetadata

    GOLDEN = File.join(__dir__, "fixtures", "group_generator", "patient_group.rb.golden")
    NASTY = 'a \ b (c) d #{e} f #@g h #$i ) ( \\' # rubocop:disable Lint/InterpolationCheck
    ESCAPED = 'a \\\\ b \(c\) d \#{e} f \#@g h \#$i \) \( \\\\'
    TEST_LITERAL = /description \[description, (%\(\n.*?\n        \))\]/m

    FakeConfigKeeper = Struct.new(:suite_module_name, :title) do
      def exclude_resource?(*) = false
    end

    FakeIGMetadata = Struct.new(:ordered_groups, :ig_test_id_prefix, :ig_module_name_prefix)

    def setup
      @previous_config_keeper = Registry.get(:config_keeper)
      Registry.register(:config_keeper, FakeConfigKeeper.new("ExampleTestKit", "Example"))
      @group = build_group
      @ig_metadata = FakeIGMetadata.new([@group], "example", "Example")
    end

    def teardown
      Registry.register(:config_keeper, @previous_config_keeper)
    end

    def test_two_argument_call_matches_main_output
      assert_equal File.read(GOLDEN), generate { |dir| GroupGenerator.generate(@ig_metadata, dir) }[:group]
    end

    def test_group_without_an_entry_matches_main_output
      other = build_group
      output = generate { |dir| GroupGenerator.generate(@ig_metadata, dir, { other => { group: NASTY } }) }

      assert_equal File.read(GOLDEN), output[:group]
    end

    def test_added_text_is_escaped_and_compiles
      group = with_descriptions[:group]

      RubyVM::InstructionSequence.compile(group)

      assert_includes group, ESCAPED
      assert_equal NASTY, eval(group[TEST_LITERAL, 1]).strip # rubocop:disable Security/Eval
    end

    def test_block_form_only_for_tests_with_added_text
      group = with_descriptions[:group]

      assert_includes group, ["      test from: :example_v100_patient_read_test do",
                              "        description [description, %(", ESCAPED,
                              '        )].compact.map(&:strip).join("\n\n")', "      end\n"].join("\n")
      assert_includes group, "      test from: :example_v100_patient_validation_test\n"
    end

    def test_group_description_is_built_in_text_then_added_markdown
      built_in = GroupGenerator.new(@group, "", @ig_metadata).description
      literal = with_descriptions[:group][/description (%\(\n.*?\n      \))\n\n      id /m, 1]

      assert_equal "\n  #{built_in}\n#{NASTY}\n\n      ", eval(literal) # rubocop:disable Security/Eval
    end

    def test_carriage_returns_survive_the_literal
      descriptions = { @group => { "example_v100_patient_read_test" => "a\r\nb\rc" } }
      group = generate { |dir| GroupGenerator.generate(@ig_metadata, dir, descriptions) }[:group]

      assert_equal "a\r\nb\rc", eval(group[TEST_LITERAL, 1]).strip # rubocop:disable Security/Eval
    end

    def test_blank_added_text_is_ignored
      descriptions = { @group => { "example_v100_patient_read_test" => "", group: " \n " } }

      assert_equal File.read(GOLDEN),
                   generate { |dir| GroupGenerator.generate(@ig_metadata, dir, descriptions) }[:group]
    end

    def test_subclass_with_three_argument_initialize_still_generates
      subclass = Class.new(GroupGenerator) do
        def initialize(group_metadata, base_output_dir, ig_metadata) # rubocop:disable Lint/UselessMethodDefinition
          super
        end
      end
      descriptions = { build_group => { group: NASTY } }

      assert_equal File.read(GOLDEN), generate { |dir| subclass.generate(@ig_metadata, dir) }[:group]
      assert_equal File.read(GOLDEN), generate { |dir| subclass.generate(@ig_metadata, dir, descriptions) }[:group]
    end

    def test_metadata_is_unchanged_by_descriptions
      assert_equal generate { |dir| GroupGenerator.generate(@ig_metadata, dir) }[:metadata],
                   with_descriptions[:metadata]
    end

    private

    def with_descriptions
      descriptions = { @group => { "example_v100_patient_read_test" => NASTY, group: NASTY } }
      generate { |dir| GroupGenerator.generate(@ig_metadata, dir, descriptions) }
    end

    def build_group
      GroupMetadata.new(
        name: "example_patient", version: "v1.0.0", reformatted_version: "v100", resource: "Patient",
        profile_url: "http://example.org/StructureDefinition/patient", profile_name: "Example Patient",
        title: "Patient", short_description: "Verify support for the Patient resource.",
        searches: [{ names: ["_id"], expectation: "SHALL" }],
        tests: [{ id: "example_v100_patient_read_test", file_name: "patient_read_test.rb" },
                { id: "example_v100_patient_validation_test", file_name: "patient_validation_test.rb" }]
      )
    end

    def generate
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "patient"))
        yield dir
        { group: File.read(File.join(dir, "patient_group.rb")),
          metadata: File.read(File.join(dir, "patient", "metadata.yml")) }
      end
    end
  end
end
