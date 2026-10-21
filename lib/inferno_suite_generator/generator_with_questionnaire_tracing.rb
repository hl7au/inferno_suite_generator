# frozen_string_literal: true

require "fileutils"
require "yaml"
require_relative "../inferno_suite_generator"
require_relative "questionnaire_usage_tracing/tracer"
require_relative "questionnaire_usage_tracing/group_generator"

module InfernoSuiteGenerator
  class Generator
    # A `Generator` that also traces how the IG's questionnaires use each
    # profile in the suite. A kit opts in by calling it instead of `Generator`:
    #
    #   require "inferno_suite_generator/generator_with_questionnaire_tracing"
    #
    #   InfernoSuiteGenerator::Generator::WithQuestionnaireTracing.generate("config/suite.json")
    #
    # Each traced group gets a "Used in questionnaires" section in its
    # description, and the trace in `<profile_identifier>/plugins.yml` under
    # `questionnaire_usage_tracing`.
    class WithQuestionnaireTracing < Generator
      PLUGINS_FILE = "plugins.yml"
      TRACE_KEY = "questionnaire_usage_tracing"

      # `{ profile_url => [trace entries] }`
      attr_reader :questionnaire_traces

      def extract_metadata
        super
        trace_questionnaires
      end

      # Traces every Questionnaire in the IG over the groups that are not
      # excluded.
      def trace_questionnaires
        @questionnaire_traces = QuestionnaireUsageTracing::Tracer.new(ig_resources, suite_groups).trace
      end

      def generate_groups
        QuestionnaireUsageTracing::QuestionnaireAwareGroupGenerator.traces = questionnaire_traces
        QuestionnaireUsageTracing::QuestionnaireAwareGroupGenerator.generate(ig_metadata, base_output_dir)
        suite_groups.each { |group| write_plugins_file(group) }
      end

      private

      # The groups that are not excluded, the same ones `GroupGenerator`
      # generates. Kept so tracing and `plugins.yml` see the same groups.
      def suite_groups
        config = Registry.get(:config_keeper)
        @suite_groups ||= ig_metadata.ordered_groups.compact
                                     .reject { |group| config.exclude_resource?(group.profile_url, group.resource) }
      end

      # A group without a trace has the key removed, so a trace from an earlier
      # run into the same folder doesn't stay behind.
      def write_plugins_file(group)
        entries = questionnaire_traces.to_h[group.profile_url].to_a
        file = PluginsFile.new(File.join(base_output_dir, Naming.snake_case_for_profile(group), PLUGINS_FILE))
        return file.delete(TRACE_KEY) if entries.empty?

        file.set(TRACE_KEY, entries.map(&:deep_stringify_keys))
      end

      # One group's `plugins.yml`. Setting or deleting a key keeps the rest of
      # an existing file, so several plugins can share it.
      class PluginsFile
        def initialize(path)
          @path = path
        end

        def set(key, value)
          FileUtils.mkdir_p(File.dirname(@path))
          File.write(@path, YAML.dump(read.merge(key => value)))
        end

        # Removes the file when no other key is left in it.
        def delete(key)
          content = read
          return unless content.key?(key)

          content.delete(key)
          content.empty? ? File.delete(@path) : File.write(@path, YAML.dump(content))
        end

        private

        def read
          (YAML.load_file(@path, aliases: true) if File.exist?(@path)) || {}
        end
      end
    end
  end
end
