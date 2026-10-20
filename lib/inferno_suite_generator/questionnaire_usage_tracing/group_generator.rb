# frozen_string_literal: true

require_relative "../generators/group_generator"
require_relative "usage_section"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # A `GroupGenerator` that adds a "Used in questionnaires" section to the
    # description of each group with a trace.
    class QuestionnaireAwareGroupGenerator < Generator::GroupGenerator
      class << self
        # `{ profile_url => [trace entries] }`, set before `generate` is called.
        attr_writer :traces

        def traces
          @traces || {}
        end
      end

      def description
        entries = self.class.traces[profile_url].to_a
        return super if entries.empty?

        "#{super}\n#{UsageSection.new(entries, group_metadata)}"
      end
    end
  end
end
