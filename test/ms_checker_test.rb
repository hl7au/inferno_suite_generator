# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"
require "ostruct"
require "inferno_suite_generator/test_utils/ms_checker"

module InfernoSuiteGenerator
  class MSCheckerTest < Minitest::Test
    Extension = Struct.new(:url)
    ElementWithExtension = Struct.new(:extension)
    TestMetadata = Struct.new(:mandatory_elements, :resource, :must_supports)

    def test_dar_found_true_when_value_has_dar_extension
      checker = build_checker
      resource = Struct.new(:valueString).new(
        ElementWithExtension.new([Extension.new(FHIRResourceNavigation::DAR_EXTENSION_URL)])
      )

      assert checker.send(:dar_found?, resource, "valueString")
    end

    def test_dar_found_true_when_primitive_fallback_returns_true
      checker = build_checker

      checker.stub(:find_a_value_at, nil) do
        checker.stub(:primitive_dar_found?, true) do
          assert checker.send(:dar_found?, Object.new, "valueString")
        end
      end
    end

    def test_dar_found_true_for_underscore_primitive_extension_path
      checker = build_checker
      primitive_extension = ElementWithExtension.new([Extension.new(FHIRResourceNavigation::DAR_EXTENSION_URL)])
      resource = Struct.new(:_valueString).new(primitive_extension)

      assert checker.send(:dar_found?, resource, "valueString")
    end

    def test_dar_found_false_when_no_dar_value_and_no_primitive_dar
      checker = build_checker

      checker.stub(:find_a_value_at, nil) do
        checker.stub(:primitive_dar_found?, false) do
          refute checker.send(:dar_found?, Object.new, "valueString")
        end
      end
    end

    private

    def build_checker
      metadata = TestMetadata.new([], "Observation", { elements: [] })
      MSChecker.new(metadata)
    end
  end
end
