# frozen_string_literal: true

require_relative "test_helper"
require "prism"
require "tmpdir"
require "inferno_suite_generator"
require "inferno_suite_generator/plugins/testing"

module InfernoSuiteGenerator
  class GroupGeneratorPluginDescriptionsTest < Minitest::Test
    include Plugins::Testing

    def setup
      @dir = Dir.mktmpdir
      @group = build_group_metadata
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

    private

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

    # The value of the %( ... ) literal passed to description in the generated group file.
    def generated_description(path)
      call = find_call(Prism.parse_file(path).value, :description)
      RubyVM::InstructionSequence.compile(call.arguments.arguments.first.slice).eval
    end

    def find_call(node, name)
      return node if node.is_a?(Prism::CallNode) && node.name == name

      node.compact_child_nodes.each do |child|
        found = find_call(child, name)
        return found if found
      end
      nil
    end
  end
end
