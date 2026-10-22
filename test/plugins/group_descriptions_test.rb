# frozen_string_literal: true

require_relative "../test_helper"
require "inferno_suite_generator"
require "inferno_suite_generator/plugins/testing"

module InfernoSuiteGenerator
  module Plugins
    class GroupDescriptionsTest < Minitest::Test
      include Testing

      def setup
        @previous_config_keeper = Registry.get(:config_keeper)
        Registry.register(:config_keeper, build_config_keeper)
        @descriptions = GroupDescriptions.new
        @group = build_group_metadata
      end

      def teardown
        Registry.register(:config_keeper, @previous_config_keeper)
      end

      def test_keeps_texts_in_add_order_across_plugins
        @descriptions.for_plugin("first").group(@group, "## One")
        @descriptions.for_plugin("second").group(@group, "## Two")
        @descriptions.for_plugin("first").group(@group, "## Three")

        assert_equal ["## One", "## Two", "## Three"], @descriptions.for(@group)
        assert_equal "## One\n\n## Two\n\n## Three", @descriptions.section(@group)
      end

      def test_groups_adds_one_text_per_group
        location = build_group_metadata(name: "example_location", resource: "Location")

        @descriptions.for_plugin("first").groups({ @group => "Patient text", location => "Location text" })

        assert_equal ["Patient text"], @descriptions.for(@group)
        assert_equal ["Location text"], @descriptions.for(location)
      end

      def test_group_without_text_has_no_texts_and_no_section
        assert_empty @descriptions.for(@group)
        assert_nil @descriptions.section(@group)
      end

      def test_ignores_nil_and_blank_text
        writer = @descriptions.for_plugin("first")
        writer.group(@group, nil)
        writer.group(@group, "")
        writer.group(@group, " \n ")

        assert_empty @descriptions.for(@group)
        assert_nil @descriptions.section(@group)
      end

      def test_section_escapes_text_for_the_group_template
        @descriptions.for_plugin("first").group(@group, "# Heading (see \\ and \#{x}, \#@y, \#$z)")

        assert_equal "# Heading \\(see \\\\ and \\\#{x}, \\\#@y, \\\#$z\\)", @descriptions.section(@group)
      end

      def test_groups_for_the_same_profile_share_one_entry
        @descriptions.for_plugin("first").group(build_group_metadata, "## One")

        assert_equal ["## One"], @descriptions.for(build_group_metadata)
      end
    end
  end
end
