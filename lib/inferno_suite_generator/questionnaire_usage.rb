# frozen_string_literal: true

require_relative "core/test_index"
require_relative "questionnaire_usage/log"
require_relative "questionnaire_usage/ast"
require_relative "questionnaire_usage/query_search"
require_relative "questionnaire_usage/trace_entry"
require_relative "questionnaire_usage/profile_matcher"
require_relative "questionnaire_usage/tracer"
require_relative "questionnaire_usage/checked_elements"
require_relative "questionnaire_usage/router"
require_relative "questionnaire_usage/delivery"
require_relative "questionnaire_usage/sections"
require_relative "questionnaire_usage/trace_files"

module InfernoSuiteGenerator
  # Traces every Questionnaire in the IG over the suite's groups and splits
  # each group's trace over its tests. Delivery decides which tests list each
  # entry and which elements count as checked, and the outputs read its
  # decisions:
  #
  # - each entry goes to the test that makes its request (Router), as a
  #   "Used in questionnaires" section in that test's description
  # - the elements items read go to the Must Support test, by element
  # - the group description gets a summary: the questionnaires, the tests that
  #   list them, and what no test checks
  #
  # Sections writes those three to the descriptions. Each traced group gets its
  # entries in <group dir>/questionnaire_usage.yml, each with the ids of the
  # tests that list it as `tested_by`, from TraceFiles.
  #
  # It reads what the test generators recorded on the groups, and adds to what
  # GroupGenerator writes, so it runs between them.
  module QuestionnaireUsage
    def self.generate(ig_resources:, groups:, descriptions:, base_output_dir:)
      if groups.any? && groups.none? { |group| Generator::TestIndex.new(group).any? }
        raise "Questionnaire usage tracing must run after the test generators: no group has a recorded test."
      end

      delivery = Delivery.new(groups, Tracer.new(ig_resources, groups).trace)
      Sections.new(delivery).write(descriptions)
      TraceFiles.new(delivery).write(base_output_dir)
    end
  end
end
