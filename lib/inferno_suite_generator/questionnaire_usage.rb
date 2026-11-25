# frozen_string_literal: true

require_relative "questionnaire_usage/sources"
require_relative "questionnaire_usage/sections"

module InfernoSuiteGenerator
  # Traces which questionnaires in the IG use each group, and writes it into the descriptions.
  module QuestionnaireUsage
    KINDS = [Query, LaunchContext, Template].freeze

    def self.descriptions(ig_resources:, groups:)
      if groups.any? && groups.none? { |group| group.tests.to_a.any? { |test| group.test_kind(test[:id]).any? } }
        raise "Questionnaire usage tracing must run after the test generators: no group has a recorded test."
      end

      Sections.new(groups, sources(ig_resources:, groups:)).to_h
    end

    def self.sources(ig_resources:, groups:)
      matcher = ProfileMatcher.new(groups, ig_resources)
      ig_resources.get_resources_by_type("Questionnaire").flat_map do |questionnaire|
        form = Form.new(questionnaire.to_hash)
        KINDS.flat_map { |kind| kind.in(form, matcher, ig_resources) }
      end
    end

    def self.log(message)
      puts "Questionnaire usage tracing: #{message}"
      nil
    end
  end
end
