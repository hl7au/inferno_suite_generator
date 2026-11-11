# frozen_string_literal: true

require_relative "core/test_index"
require_relative "questionnaire_usage/ast"
require_relative "questionnaire_usage/fhir_query"
require_relative "questionnaire_usage/profile_matcher"
require_relative "questionnaire_usage/trace"
require_relative "questionnaire_usage/tracer"
require_relative "questionnaire_usage/sections"

module InfernoSuiteGenerator
  # Traces every Questionnaire in the IG over the suite's groups and writes "Used in questionnaires" sections to the
  # tests that make each source's request, the Must Support test and the group. It reads the tests the generators
  # recorded and adds to what GroupGenerator writes, so it runs between them.
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

    def self.write(trace, groups:, descriptions:)
      Sections.new(groups, trace).write(descriptions)
    end
  end
end
