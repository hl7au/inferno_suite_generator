# frozen_string_literal: true

require_relative "test_helper"
require "prism"
require "inferno/utils/markdown_formatter"
require "tmpdir"
require "inferno_suite_generator"
require "inferno_suite_generator/plugins/testing"

module InfernoSuiteGenerator
  # The part of an Inferno test class a `test from:` block touches: a description setter that formats
  # Markdown as Inferno's does.
  class InfernoTestStandIn
    extend Inferno::Utils::MarkdownFormatter

    def self.description(new_description = nil)
      return @description if new_description.nil?

      @description = format_markdown(new_description)
    end
  end

  # Reads the descriptions back out of a generated group file.
  module GeneratedGroupFile
    # The value of the %( ... ) literal passed to description in the group class.
    def generated_description(path)
      call = find_call(path) { |node| node.name == :description }
      RubyVM::InstructionSequence.compile(call.arguments.arguments.first.slice).eval
    end

    # Runs the block the group file passes to `test from: :id` on a stand-in for the test class and returns
    # the description it ends up with.
    def description_after_block(path, id, parent_description)
      test_class = Class.new(InfernoTestStandIn)
      test_class.description(parent_description)
      test_class.class_eval(find_test_from(path, id).block.body.slice)
      test_class.description
    end

    def find_test_from(path, id)
      find_call(path) do |node|
        node.name == :test && node.arguments.arguments.first.elements.first.value.unescaped == id.to_s
      end
    end

    def find_call(path, &)
      calls(Prism.parse_file(path).value).find(&)
    end

    def calls(node)
      own = node.is_a?(Prism::CallNode) ? [node] : []
      own + node.compact_child_nodes.flat_map { |child| calls(child) }
    end
  end

  class GroupGeneratorPluginDescriptionsTest < Minitest::Test
    include Plugins::Testing
    include GeneratedGroupFile

    def setup
      @dir = Dir.mktmpdir
      @group = build_group_metadata(
        tests: [{ id: "example_patient_read_test", file_name: "patient_read_test.rb" },
                { id: "example_patient_validation_test", file_name: "patient_validation_test.rb" }]
      )
      @descriptions = Plugins::GroupDescriptions.new
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def test_description_is_unchanged_without_plugin_text
      with_config_keeper do
        generator = build_generator

        assert_equal built_in_description(generator), generator.description
      end
    end

    def test_description_appends_plugin_text_after_a_blank_line
      with_config_keeper do
        @descriptions.for_plugin("first").group(@group, "## Extra")
        generator = build_generator

        assert_equal "#{built_in_description(generator)}\n## Extra\n", generator.description
      end
    end

    def test_description_keeps_plugin_texts_in_order
      with_config_keeper do
        @descriptions.for_plugin("first").group(@group, "## First")
        @descriptions.for_plugin("second").group(@group, "## Second")

        assert build_generator.description.end_with?("\n## First\n\n## Second\n")
      end
    end

    def test_generated_file_is_valid_ruby_and_reads_plugin_text_back
      text = "## Usage (see \\ and \#{x}, \#@y, \#$z)\n\n- Item (one)"
      with_config_keeper do
        @descriptions.for_plugin("first").group(@group, text)
        FileUtils.mkdir_p(File.join(@dir, "patient"))

        Generator::GroupGenerator.generate(build_ig_metadata(groups: [@group]), @dir, @descriptions)
      end
      path = File.join(@dir, "patient_group.rb")

      assert RubyVM::InstructionSequence.compile_file(path)
      assert generated_description(path).rstrip.end_with?("\n\n#{text}")
    end

    def test_tests_without_plugin_text_keep_plain_test_from_lines
      path = generate_group_file

      assert_equal <<~RUBY.lines.map(&:strip), test_lines(path)
        test from: :example_patient_read_test
        test from: :example_patient_validation_test
      RUBY
    end

    def test_test_text_is_appended_to_that_test_only
      text = "## Usage (see \\ and \#{x}, \#@y, \#$z)\n\n- Item (one)\n  - Nested"
      @descriptions.for_plugin("first").test(@group, "example_patient_read_test", text)
      path = generate_group_file

      assert RubyVM::InstructionSequence.compile_file(path)
      assert_includes test_lines(path), "test from: :example_patient_validation_test"
      assert_equal "Reads a Patient.\n\n#{text}",
                   description_after_block(path, :example_patient_read_test, "\n        Reads a Patient.\n      ")
    end

    def test_test_text_is_appended_to_a_test_with_a_single_line_description
      @descriptions.for_plugin("first").test(@group, "example_patient_read_test", "## One")
      @descriptions.for_plugin("second").test(@group, "example_patient_read_test", "## Two")
      path = generate_group_file

      assert_equal "A server SHALL support read.\n\n## One\n\n## Two",
                   description_after_block(path, :example_patient_read_test, "A server SHALL support read.")
    end

    private

    def generate_group_file
      with_config_keeper do
        FileUtils.mkdir_p(File.join(@dir, "patient"))
        Generator::GroupGenerator.generate(build_ig_metadata(groups: [@group]), @dir, @descriptions)
      end
      File.join(@dir, "patient_group.rb")
    end

    def test_lines(path)
      File.readlines(path).map(&:strip).select { |line| line.start_with?("test from:") }
    end

    def build_generator
      Generator::GroupGenerator.new(@group, @dir, build_ig_metadata(groups: [@group]), descriptions: @descriptions)
    end

    def built_in_description(generator)
      Helpers.get_group_description_text(
        generator.title, generator.resource_type, generator.profile_name, @group.version, generator.profile_url,
        generator.required_searches, generator.search_param_name_string, generator.search_validation_resource_type,
        generator.resource_type
      )
    end
  end
end
