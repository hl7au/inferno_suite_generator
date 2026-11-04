# frozen_string_literal: true

require_relative "questionnaire_usage/log"
require_relative "questionnaire_usage/ast"
require_relative "questionnaire_usage/query_search"
require_relative "questionnaire_usage/profile_matcher"
require_relative "questionnaire_usage/tracer"
require_relative "questionnaire_usage/forms"
require_relative "questionnaire_usage/usage_section"
require_relative "questionnaire_usage/element_reads"
require_relative "questionnaire_usage/router"
require_relative "questionnaire_usage/test_sections"
require_relative "questionnaire_usage/group_summary"
require_relative "questionnaire_usage/group_trace"
require_relative "questionnaire_usage/delivery"

module InfernoSuiteGenerator
  # Traces every Questionnaire in the IG over the suite's groups and splits
  # each group's trace over its tests. Delivery decides which tests list each
  # entry, and the outputs read its decisions:
  #
  # - each entry goes to the test that makes its request (Router), as a
  #   "Used in questionnaires" section in that test's description
  # - the elements items read go to the Must Support test, by element
  # - the group description gets a GroupSummary: the questionnaires, the
  #   tests that list them, and what no test checks
  #
  # Each traced group gets its entries in <group dir>/questionnaire_usage.yml,
  # each with the ids of the tests that list it as `tested_by`.
  module QuestionnaireUsage
    def self.generate(ig_resources:, groups:, descriptions:, base_output_dir:)
      delivery = Delivery.new(groups, Tracer.new(ig_resources, groups).trace)
      delivery.each_group do |group, placements|
        GroupTrace.new(group, placements).write(descriptions, base_output_dir)
      end
      TestSections.new(delivery.test_listings).write(descriptions)
    end
  end
end
