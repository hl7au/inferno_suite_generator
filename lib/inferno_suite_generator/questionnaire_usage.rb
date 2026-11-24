# frozen_string_literal: true

require "fhirpath"
require_relative "questionnaire_usage/chain"
require_relative "questionnaire_usage/query"
require_relative "questionnaire_usage/include"
require_relative "questionnaire_usage/scope"
require_relative "questionnaire_usage/form"
require_relative "questionnaire_usage/launch_context"
require_relative "questionnaire_usage/template"
require_relative "questionnaire_usage/codes"
require_relative "questionnaire_usage/entries"
require_relative "questionnaire_usage/checked_elements"
require_relative "questionnaire_usage/trace"
require_relative "questionnaire_usage/group_description"

module InfernoSuiteGenerator
  # Traces which SDC questionnaire items in the IG depend on the requests the generated tests make,
  # and returns the Markdown that GroupGenerator adds to group and test descriptions.
  module QuestionnaireUsage
    ORDER_ERROR = "Questionnaire usage tracing must run after the test generators: no group has a recorded test."

    # Returns { group_metadata => { test_id_string | :group => markdown } }; writes no files.
    def self.descriptions(ig_resources:, groups:)
      return {} if groups.empty?

      ensure_tests_recorded(groups)
      describe(groups, Trace.new(placements(Form.load(ig_resources), groups, Matcher.new(ig_resources))))
    end

    def self.describe(groups, trace)
      groups.to_h { |group| [group, GroupDescription.new(group, trace).to_h] }.reject { |_group, text| text.empty? }
    end

    def self.ensure_tests_recorded(groups)
      raise ORDER_ERROR unless groups.any? { |group| recorded?(group) }
    end

    def self.placements(forms, groups, matcher)
      forms.flat_map(&:sources).select(&:shown?).flat_map { |source| place(source, groups, matcher) }
    end

    def self.place(source, groups, matcher)
      matcher.fits(source, groups).map { |group| source.placement(group, groups) }
    end

    def self.recorded?(group)
      [*group.tests].any? { |test| group.test_kind(test[:id]).any? }
    end

    def self.log(message)
      puts "Questionnaire usage tracing: #{message}"
    end

    # The node a log line names: :root, or an item's linkId (nil when it has none).
    def self.node_label(key) = key == :root ? "root" : (key.presence || "an item without linkId")

    # The string at hash[key][key2]…, or nil when it is absent, empty or not a string.
    def self.text(hash, *keys)
      value = dig(hash, keys)
      value if value.is_a?(String) && !value.empty?
    end

    # The Hash entries of the array at hash[key], or [] when it is not an array.
    def self.list(hash, key)
      value = dig(hash, [key])
      value.is_a?(Array) ? value.grep(Hash) : []
    end

    def self.dig(hash, keys)
      keys.reduce(hash) { |node, key| node.is_a?(Hash) ? node[key] : nil }
    end
  end
end
