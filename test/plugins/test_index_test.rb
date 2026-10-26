# frozen_string_literal: true

require_relative "../test_helper"
require "inferno_suite_generator"
require "inferno_suite_generator/plugins/testing"

module InfernoSuiteGenerator
  module Plugins
    class TestIndexTest < Minitest::Test
      include Testing

      def setup
        @group = build_group_metadata
        @group.add_test(id: "patient_read_test", file_name: "patient_read_test.rb", kind: "read")
        @group.add_test(id: "patient_name_search_test", file_name: "a.rb", kind: "search", search_names: ["name"])
        @group.add_test(id: "patient_birthdate_name_search_test", file_name: "b.rb", kind: "search",
                        search_names: %w[birthdate name])
        @group.add_test(id: "patient_custom_test", file_name: "patient_custom_test.rb")
        @index = TestIndex.new(@group)
      end

      def test_finds_a_test_by_kind
        assert_equal "patient_read_test", @index.find("read")
      end

      def test_finds_a_search_test_by_parameter_names_in_any_order
        assert_equal "patient_birthdate_name_search_test", @index.find("search", search_names: %w[name birthdate])
        assert_equal "patient_name_search_test", @index.find("search", search_names: ["name"])
      end

      def test_all_lists_matching_tests_in_group_order
        assert_equal %w[patient_name_search_test patient_birthdate_name_search_test], @index.all("search")
      end

      def test_returns_nil_when_no_test_matches
        assert_nil @index.find("search", search_names: ["gender"])
        assert_nil @index.find("must_support")
      end

      def test_a_test_added_without_a_kind_is_never_found
        assert_empty @group.test_kind("patient_custom_test")
        assert_equal ["patient_read_test"], @index.all("read")
      end

      def test_kinds_stay_out_of_metadata_yml
        refute_includes YAML.dump(@group.to_hash), "search_names"
        assert_equal({ id: "patient_read_test", file_name: "patient_read_test.rb" }, @group.tests.first)
      end
    end
  end
end
