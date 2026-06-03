# frozen_string_literal: true

require_relative "test_helper"
require "active_support/all"
require "inferno_suite_generator/utils/fhir_resource_navigation"
require "fhir_models"
require "json"
require "ostruct"

module InfernoSuiteGenerator
  # Tests for FHIRResourceNavigation helpers.
  class FHIRResourceNavigationTest < Minitest::Test
    METADATA_FIXTURE = "test/fixtures/metadata.json"
    OBSERVATION_FIXTURE = "test/fixtures/observation.json"

    # Minimal include host for module methods under test.
    class NavigationTestHelper
      include FHIRResourceNavigation
    end

    VALUE_DEFINITION = { path: %w[coding code], value: "foo", extra: 1 }.freeze
    VALUE_DEFINITION_WITHOUT_EXTRA = { path: %w[coding code], value: "foo" }.freeze

    def setup
      @helper = NavigationTestHelper.new
      @metadata = load_metadata
      @observation = load_observation
    end

    def test_vd_merge_path_returns_new_hash_with_same_attributes
      merged = @helper.vd_merge_path(VALUE_DEFINITION)

      refute_same VALUE_DEFINITION, merged
      assert_equal VALUE_DEFINITION, merged
    end

    def test_vd_merge_path_dupes_path_array
      merged = @helper.vd_merge_path(VALUE_DEFINITION_WITHOUT_EXTRA)

      refute_same VALUE_DEFINITION_WITHOUT_EXTRA[:path], merged[:path]
    end

    def test_vd_merge_path_isolates_path_mutations
      merged = @helper.vd_merge_path(VALUE_DEFINITION_WITHOUT_EXTRA)
      merged[:path].shift

      assert_equal %w[coding code], VALUE_DEFINITION_WITHOUT_EXTRA[:path]
    end

    def test_verify_slice_by_values_matches_vscat_category
      category = @observation.category.first
      value_definitions = value_definitions_for(slice_named("VSCat"))

      assert @helper.verify_slice_by_values(category, value_definitions, metadata: @metadata)
    end

    def test_verify_slice_by_values_matches_systolic_bp_component
      component = component_with_loinc("8480-6")
      value_definitions = value_definitions_for(slice_named("SystolicBP"))

      assert @helper.verify_slice_by_values(component, value_definitions, metadata: @metadata)
    end

    def test_verify_slice_by_values_matches_diastolic_bp_component
      component = component_with_loinc("8462-4")
      value_definitions = value_definitions_for(slice_named("DiastolicBP"))

      assert @helper.verify_slice_by_values(component, value_definitions, metadata: @metadata)
    end

    def test_verify_slice_by_values_rejects_wrong_component
      component = component_with_loinc("8462-4")
      value_definitions = value_definitions_for(slice_named("SystolicBP"))

      refute @helper.verify_slice_by_values(component, value_definitions, metadata: @metadata)
    end

    def test_slice_matches_discriminator_for_vscat
      category = @observation.category.first
      discriminator = slice_named("VSCat")[:discriminator]

      assert @helper.slice_matches_discriminator?(category, discriminator, metadata: @metadata)
    end

    def test_slice_matches_discriminator_for_systolic_bp
      component = component_with_loinc("8480-6")
      discriminator = slice_named("SystolicBP")[:discriminator]

      assert @helper.slice_matches_discriminator?(component, discriminator, metadata: @metadata)
    end

    def test_find_a_value_at_resolves_category_vscat_slice
      category = @helper.find_a_value_at(@observation, "category:VSCat", metadata: @metadata)

      assert category
      assert_equal "vital-signs", category.coding.first.code
    end

    def test_find_a_value_at_resolves_component_systolic_bp_slice
      component = @helper.find_a_value_at(@observation, "component:SystolicBP", metadata: @metadata)

      assert component
      assert_equal 160, component.valueQuantity.value
    end

    def test_find_a_value_at_resolves_code_b_pcode_slice
      coding = @helper.find_a_value_at(@observation, "code.coding:BPCode", metadata: @metadata)

      assert coding
      assert_equal "85354-9", coding.code
      assert_equal "http://loinc.org", coding.system
    end

    def test_verify_slice_by_values_does_not_mutate_source_value_definitions
      component = component_with_loinc("8480-6")
      source_definitions = raw_value_definitions_for(slice_named("SystolicBP"))
      expected_paths = source_definitions.map { |definition| definition[:path] }

      2.times do
        @helper.verify_slice_by_values(
          component,
          source_definitions.map { |definition| definition.merge(path: definition[:path].split(".")) },
          metadata: @metadata
        )
      end

      assert_equal expected_paths, (source_definitions.map { |definition| definition[:path] })
    end

    private

    def load_metadata
      OpenStruct.new(json_to_hash(METADATA_FIXTURE))
    end

    def load_observation
      FHIR::Observation.new(json_to_hash(OBSERVATION_FIXTURE, symbolize_names: false))
    end

    def json_to_hash(file_path, symbolize_names: true)
      JSON.parse(File.read(file_path), symbolize_names:)
    end

    def slice_named(name)
      @metadata.must_supports[:slices].find { |slice| slice[:slice_name] == name }
    end

    def value_definitions_for(slice)
      slice[:discriminator][:values].map { |definition| definition.merge(path: definition[:path].split(".")) }
    end

    def raw_value_definitions_for(slice)
      slice[:discriminator][:values].map(&:dup)
    end

    def component_with_loinc(code)
      @observation.component.find do |component|
        component.code.coding.any? { |coding| coding.code == code && coding.system == "http://loinc.org" }
      end
    end
  end
end
