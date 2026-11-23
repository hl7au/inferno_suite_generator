# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  class GroupMetadataFindTestTest < Minitest::Test
    GroupMetadata = InfernoSuiteGenerator::Generator::GroupMetadata

    def group(resource = "Patient")
      GroupMetadata.new(resource:, searches: [])
    end

    def group_with_tests
      group.tap do |metadata|
        metadata.add_test(id: "read_test", file_name: "read.rb", kind: "read")
        metadata.add_test(id: "search_a", file_name: "a.rb", kind: "search", search_names: %w[patient code])
        metadata.add_test(id: "search_b", file_name: "b.rb", kind: "search", search_names: %w[patient])
        metadata.add_test(id: "update", file_name: "u.rb", kind: "update", option: "update")
        metadata.add_test(id: "update_new", file_name: "un.rb", kind: "update", option: "update_new")
      end
    end

    def test_test_kind_returns_recorded_kind_and_details
      assert_equal({ kind: "search", search_names: %w[patient code] }, group_with_tests.test_kind("search_a"))
    end

    def test_test_kind_is_empty_for_test_added_without_kind
      metadata = group
      metadata.add_test(id: "plain", file_name: "plain.rb")

      assert_empty metadata.test_kind("plain")
    end

    def test_add_test_without_kind_keeps_main_behaviour
      metadata = group("Provenance")
      metadata.add_test(id: "search", file_name: "search.rb")
      metadata.add_test(id: "read", file_name: "read.rb")

      assert_equal [{ id: "read", file_name: "read.rb" }, { id: "search", file_name: "search.rb" }], metadata.tests
    end

    def test_add_test_with_kind_keeps_tests_entries_and_delayed_ordering
      metadata = group("Provenance")
      metadata.add_test(id: "search", file_name: "search.rb", kind: "search", search_names: ["target"])
      metadata.add_test(id: "read", file_name: "read.rb", kind: "read")

      assert_equal [{ id: "read", file_name: "read.rb" }, { id: "search", file_name: "search.rb" }], metadata.tests
    end

    def test_find_test_matches_search_names_in_any_order
      assert_equal({ id: "search_a", kind: "search", search_names: %w[patient code] },
                   group_with_tests.find_test("search", search_names: %w[code patient]))
    end

    def test_find_test_returns_first_match_in_test_order
      assert_equal "search_a", group_with_tests.find_test("search")[:id]
    end

    def test_find_test_matches_update_option
      assert_equal "update", group_with_tests.find_test("update", option: "update")[:id]
    end

    def test_find_test_returns_nil_when_nothing_matches
      metadata = group_with_tests

      assert_nil metadata.find_test("search", search_names: %w[code])
      assert_nil metadata.find_test("create")
      assert_nil metadata.find_test("read", option: "update")
    end

    def test_find_test_raises_for_unknown_kind
      assert_raises(ArgumentError) { group_with_tests.find_test("searching") }
    end

    def test_kinds_stay_out_of_hash_and_yaml
      metadata = group_with_tests
      plain = group
      metadata.tests.each { |test| plain.add_test(**test) }

      assert_equal YAML.dump(plain.to_hash), YAML.dump(metadata.to_hash)
    end

    def test_group_rebuilt_from_hash_has_no_kinds
      rebuilt = GroupMetadata.new(YAML.safe_load(YAML.dump(group_with_tests.to_hash), permitted_classes: [Symbol]))

      assert_empty rebuilt.test_kind("search_a")
      assert_nil rebuilt.find_test("search")
    end
  end
end
