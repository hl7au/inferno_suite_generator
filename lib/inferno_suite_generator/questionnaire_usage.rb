# frozen_string_literal: true

require_relative "core/test_index"
require_relative "questionnaire_usage/ast"
require_relative "questionnaire_usage/fhir_query"
require_relative "questionnaire_usage/trace_entry"
require_relative "questionnaire_usage/profile_matcher"
require_relative "questionnaire_usage/tracer"
require_relative "questionnaire_usage/sections"

module InfernoSuiteGenerator
  # Traces every Questionnaire in the IG over the suite's groups and splits
  # each group's trace over its tests. Delivery decides which tests list each
  # entry and which elements count as checked, and the outputs read its
  # decisions:
  #
  # - each entry goes to the test that makes its request, as a
  #   "Used in questionnaires" section in that test's description
  # - the elements items read go to the Must Support test, by element
  # - the group description gets a summary: the questionnaires, the tests that
  #   list them, and what no test checks
  #
  # Sections writes those three to the descriptions.
  #
  # It reads what the test generators recorded on the groups, and adds to what
  # GroupGenerator writes, so it runs between them.
  module QuestionnaireUsage
    def self.generate(ig_resources:, groups:, descriptions:)
      if groups.any? && groups.none? { |group| Generator::TestIndex.new(group).any? }
        raise "Questionnaire usage tracing must run after the test generators: no group has a recorded test."
      end

      write(Tracer.new(ig_resources, groups).trace, groups:, descriptions:)
    end

    # Prints a tracing message. Returns `nil`, so a caller can `return log(...)`.
    def self.log(message)
      puts "Questionnaire usage tracing: #{message}"
      nil
    end

    # Writes the sections for traces: `{ profile_url => [TraceEntry] }`, from `Tracer#trace`.
    def self.write(traces, groups:, descriptions:)
      Sections.new(groups, traces).write(descriptions)
    end
  end
end
