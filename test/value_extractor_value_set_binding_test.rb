# frozen_string_literal: true

require_relative "test_helper"
require "fhir_models"
require "active_support/core_ext/object/blank"
require "inferno_suite_generator/extractors/value_extractor"

module InfernoSuiteGenerator
  class ValueExtractorValueSetBindingTest < Minitest::Test
    ValueExactor = InfernoSuiteGenerator::Generator::ValueExactor

    # Minimal IGResources stand-in: looks ValueSets / CodeSystems up by url.
    class IGResourcesDouble
      def initialize(value_sets: [], code_systems: [])
        @value_sets = value_sets
        @code_systems = code_systems
      end

      def value_set_by_url(url) = @value_sets.find { |vs| vs.url == url }
      def code_system_by_url(url) = @code_systems.find { |cs| cs.url == url }
    end

    def bound_element(value_set_url)
      FHIR::ElementDefinition.new(
        "path" => "Observation.code",
        "binding" => { "strength" => "required", "valueSet" => value_set_url }
      )
    end

    def value_set(url, includes)
      FHIR::ValueSet.new("url" => url, "compose" => { "include" => includes })
    end

    def extractor(ig_resources)
      ValueExactor.new(ig_resources, "Observation", [])
    end

    def test_collects_inline_concept_codes
      vs = value_set("http://vs/inline",
                     [{ "system" => "http://sys/a", "concept" => [{ "code" => "a1" }, { "code" => "a2" }] }])
      subject = extractor(IGResourcesDouble.new(value_sets: [vs]))

      assert_equal %w[a1 a2], subject.values_from_value_set_binding(bound_element("http://vs/inline"))
    end

    def test_expands_a_referenced_code_system_when_the_include_has_no_filter
      vs = value_set("http://vs/sys", [{ "system" => "http://sys/b" }])
      cs = FHIR::CodeSystem.new("url" => "http://sys/b", "concept" => [{ "code" => "b1" }, { "code" => "b2" }])
      subject = extractor(IGResourcesDouble.new(value_sets: [vs], code_systems: [cs]))

      assert_equal %w[b1 b2], subject.values_from_value_set_binding(bound_element("http://vs/sys"))
    end

    def test_ignores_includes_that_carry_a_filter
      vs = value_set("http://vs/filtered", [
                       { "system" => "http://sys/c", "filter" => [{ "property" => "concept", "op" => "is-a", "value" => "x" }] }
                     ])
      subject = extractor(IGResourcesDouble.new(value_sets: [vs]))

      assert_empty subject.values_from_value_set_binding(bound_element("http://vs/filtered"))
    end

    def test_recurses_into_nested_value_sets
      nested = value_set("http://vs/nested", [{ "system" => "http://sys/n", "concept" => [{ "code" => "n1" }] }])
      outer = value_set("http://vs/outer", [
                          { "system" => "http://sys/a", "concept" => [{ "code" => "a1" }] },
                          { "valueSet" => ["http://vs/nested"] }
                        ])
      subject = extractor(IGResourcesDouble.new(value_sets: [nested, outer]))

      assert_equal %w[a1 n1], subject.values_from_value_set_binding(bound_element("http://vs/outer"))
    end

    def test_returns_empty_when_the_value_set_is_not_found
      subject = extractor(IGResourcesDouble.new)

      assert_empty subject.values_from_value_set_binding(bound_element("http://vs/missing"))
    end

    def test_returns_empty_when_the_element_has_no_binding
      subject = extractor(IGResourcesDouble.new)

      assert_empty subject.values_from_value_set_binding(FHIR::ElementDefinition.new("path" => "Observation.code"))
    end

    def test_deduplicates_codes_across_includes
      vs = value_set("http://vs/dup", [
                       { "system" => "http://sys/a", "concept" => [{ "code" => "x" }, { "code" => "y" }] },
                       { "system" => "http://sys/b", "concept" => [{ "code" => "y" }, { "code" => "z" }] }
                     ])
      subject = extractor(IGResourcesDouble.new(value_sets: [vs]))

      assert_equal %w[x y z], subject.values_from_value_set_binding(bound_element("http://vs/dup"))
    end
  end
end
