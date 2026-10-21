# frozen_string_literal: true

require_relative "../generators/group_generator"
require_relative "usage_section"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # A `GroupGenerator` that adds a "Used in questionnaires" section to the
    # description of each group with a trace that has something to show.
    class QuestionnaireAwareGroupGenerator < Generator::GroupGenerator
      # `traces` is `{ profile_url => [trace entries] }`.
      def self.generate(ig_metadata, base_output_dir, traces)
        suite_groups(ig_metadata).each { |group| new(group, base_output_dir, ig_metadata, traces:).generate }
      end

      def initialize(group_metadata, base_output_dir, ig_metadata, traces: {})
        super(group_metadata, base_output_dir, ig_metadata)
        @traces = traces
      end

      def description
        section = UsageSection.new(@traces.to_h[profile_url].to_a, group_metadata)
        return super if section.empty?

        "#{super}\n#{section}"
      end
    end
  end
end
