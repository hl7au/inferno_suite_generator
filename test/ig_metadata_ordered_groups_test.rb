# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  class IGMetadataOrderedGroupsTest < Minitest::Test
    GroupMetadata = InfernoSuiteGenerator::Generator::GroupMetadata
    IGMetadata = InfernoSuiteGenerator::Generator::IGMetadata

    FakeConfigKeeper = Struct.new(:groups_order)

    def setup
      @previous_config_keeper = Registry.get(:config_keeper)
    end

    def teardown
      Registry.register(:config_keeper, @previous_config_keeper)
    end

    def test_keeps_declaration_order_when_groups_order_is_absent
      register_config_keeper(nil)

      assert_equal(
        %w[au_core_patient au_core_bodyweight au_core_bloodpressure au_core_condition au_core_organization],
        build_metadata.ordered_groups.map(&:name)
      )
    end

    def test_keeps_declaration_order_when_groups_order_is_empty
      register_config_keeper([])

      assert_equal(
        %w[au_core_patient au_core_bodyweight au_core_bloodpressure au_core_condition au_core_organization],
        build_metadata.ordered_groups.map(&:name)
      )
    end

    def test_moves_listed_groups_first_in_listed_order_and_keeps_the_rest_stable
      register_config_keeper(%w[au_core_condition au_core_bloodpressure])

      assert_equal(
        %w[au_core_patient au_core_condition au_core_bloodpressure au_core_bodyweight au_core_organization],
        build_metadata.ordered_groups.map(&:name)
      )
    end

    def test_an_entry_matching_a_resource_type_moves_every_group_of_that_type
      register_config_keeper(%w[Observation])

      assert_equal(
        %w[au_core_patient au_core_bodyweight au_core_bloodpressure au_core_condition au_core_organization],
        build_metadata.ordered_groups.map(&:name)
      )
    end

    def test_reorders_a_resource_family_ahead_of_an_earlier_group
      non_delayed = [
        group("au_core_condition", "Condition"),
        group("au_core_bodyweight", "Observation"),
        group("au_core_bloodpressure", "Observation")
      ]
      register_config_keeper(%w[Observation])

      assert_equal(
        %w[au_core_patient au_core_bodyweight au_core_bloodpressure au_core_condition au_core_organization],
        build_metadata(non_delayed:).ordered_groups.map(&:name)
      )
    end

    def test_ignores_unknown_entries
      register_config_keeper(%w[au_core_does_not_exist NotAResource au_core_condition])

      assert_equal(
        %w[au_core_patient au_core_condition au_core_bodyweight au_core_bloodpressure au_core_organization],
        build_metadata.ordered_groups.map(&:name)
      )
    end

    def test_never_moves_the_patient_group_or_the_delayed_groups
      register_config_keeper(%w[au_core_patient au_core_organization])

      ordered = build_metadata.ordered_groups.map(&:name)

      assert_equal("au_core_patient", ordered.first)
      assert_equal("au_core_organization", ordered.last)
    end

    private

    def register_config_keeper(groups_order)
      Registry.register(:config_keeper, FakeConfigKeeper.new(groups_order))
    end

    def group(name, resource, delayed: false)
      GroupMetadata.new(name:, resource:, searches: delayed ? [] : [{ names: %w[patient] }])
    end

    def default_non_delayed
      [
        group("au_core_bodyweight", "Observation"),
        group("au_core_bloodpressure", "Observation"),
        group("au_core_condition", "Condition")
      ]
    end

    def build_metadata(non_delayed: default_non_delayed)
      IGMetadata.new.tap do |metadata|
        metadata.groups = [
          group("au_core_patient", "Patient"),
          *non_delayed,
          group("au_core_organization", "Organization", delayed: true)
        ]
      end
    end
  end
end
