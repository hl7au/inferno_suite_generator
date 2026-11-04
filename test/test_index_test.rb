# frozen_string_literal: true

require_relative "test_helper"
require_relative "generator_fixtures"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  class Generator
    class TestIndexTest < Minitest::Test
      include GeneratorFixtures

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
        assert_equal "patient_read_test", @index.find("read").id
      end

      def test_finds_a_search_test_by_parameter_names_in_any_order
        assert_equal "patient_birthdate_name_search_test", @index.find("search", search_names: %w[name birthdate]).id
        assert_equal "patient_name_search_test", @index.find("search", search_names: ["name"]).id
      end

      def test_finds_the_first_match_in_group_order
        assert_equal "patient_name_search_test", @index.find("search").id
      end

      def test_a_found_test_has_its_kind_and_recorded_details
        test = @index.find("search", search_names: %w[name birthdate])

        assert_equal "search", test.kind
        assert_equal({ search_names: %w[birthdate name] }, test.details)
      end

      def test_an_unknown_kind_raises
        error = assert_raises(ArgumentError) { @index.find("raed") }

        assert_includes error.message, "raed"
      end

      def test_returns_nil_when_no_test_matches
        assert_nil @index.find("search", search_names: ["gender"])
        assert_nil @index.find("must_support")
      end

      def test_a_test_added_without_a_kind_is_never_found
        custom = build_group_metadata
        custom.add_test(id: "patient_custom_test", file_name: "patient_custom_test.rb")

        assert_nil TestIndex.new(custom).find("read")
      end

      def test_any_says_whether_the_group_recorded_a_test_with_a_kind
        custom = build_group_metadata
        custom.add_test(id: "patient_custom_test", file_name: "patient_custom_test.rb")

        assert_predicate @index, :any?
        refute_predicate TestIndex.new(custom), :any?
        refute_predicate TestIndex.new(build_group_metadata), :any?
      end

      def test_kinds_stay_out_of_metadata_yml
        refute_includes YAML.dump(@group.to_hash), "search_names"
        assert_equal({ id: "patient_read_test", file_name: "patient_read_test.rb" }, @group.tests.first)
      end
    end
  end
end
