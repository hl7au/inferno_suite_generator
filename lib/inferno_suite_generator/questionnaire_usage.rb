# frozen_string_literal: true

require_relative "questionnaire_usage/sources"
require_relative "questionnaire_usage/sections"

module InfernoSuiteGenerator
  # Finds what every Questionnaire in the IG reads from the server or writes to it, over the suite's groups, and
  # writes "Used in questionnaires" sections for the tests that make the same requests, the Must Support test and
  # the group.
  module QuestionnaireUsage
    # The kinds of source, in the order a form's sources are listed.
    KINDS = [Query, LaunchContext, Template].freeze

    # The Markdown to add to descriptions, as `{ group => { test id or :group => Markdown } }`. It reads the tests
    # the generators recorded and GroupGenerator writes what it returns, so it runs between them.
    def self.descriptions(ig_resources:, groups:)
      if groups.any? && groups.none? { |group| group.test_kinds.any? }
        raise "Questionnaire usage tracing must run after the test generators: no group has a recorded test."
      end

      Sections.new(groups, sources(ig_resources:, groups:)).to_h
    end

    # The Sources of every questionnaire that some group fits, in document order.
    def self.sources(ig_resources:, groups:)
      matcher = ProfileMatcher.new(groups, ig_resources)
      ig_resources.get_resources_by_type("Questionnaire").flat_map do |questionnaire|
        form = Form.new(questionnaire.to_hash)
        KINDS.flat_map { |kind| kind.in(form, matcher, ig_resources) }
      end
    end

    # Prints a tracing message. Returns `nil`, so a caller can `return log(...)`.
    def self.log(message)
      puts "Questionnaire usage tracing: #{message}"
      nil
    end
  end
end
