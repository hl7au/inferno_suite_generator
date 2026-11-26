# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  class GroupMetadataToHashTest < Minitest::Test
    GroupMetadata = InfernoSuiteGenerator::Generator::GroupMetadata

    def test_keeps_update_create_attributes_when_update_create_is_true
      hash = GroupMetadata.new(resource: "Observation", update_create: true, update_create_expectation: "SHALL").to_hash

      assert_equal true, hash[:update_create]
      assert_equal "SHALL", hash[:update_create_expectation]
    end

    def test_omits_update_create_attributes_when_update_create_is_false
      hash = GroupMetadata.new(resource: "Observation", update_create: false, update_create_expectation: "MAY").to_hash

      refute hash.key?(:update_create)
      refute hash.key?(:update_create_expectation)
      assert_equal "Observation", hash[:resource]
    end
  end
end
