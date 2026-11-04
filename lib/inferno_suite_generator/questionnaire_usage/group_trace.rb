# frozen_string_literal: true

require "active_support/core_ext/hash/keys"
require "fileutils"
require "yaml"
require_relative "../utils/naming"
require_relative "element_reads"
require_relative "group_summary"
require_relative "usage_section"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # One group's trace entries and the tests they go to.
    class GroupTrace
      FILE_NAME = "questionnaire_usage.yml"

      def initialize(group, entries, router, tests)
        @group = group
        @entries = entries
        @must_support = router.must_support_test(group)
        @destinations = entries.select { |entry| UsageSection.shown?(entry) }
                               .each_with_object({}.compare_by_identity) do |entry, destinations|
          destinations[entry] = router.source_test(group, entry)
        end
        @destinations.each { |entry, destination| tests.add(destination, entry, group) if destination }
      end

      def write(descriptions, base_output_dir)
        write_must_support(descriptions)
        write_trace_file(base_output_dir)
        summary = GroupSummary.new(@group, @entries, @destinations, @must_support)
        descriptions.group(@group, summary.markdown) unless summary.empty?
      end

      private

      def write_must_support(descriptions)
        section = MustSupportSection.new(@entries, @group)
        descriptions.test(@group, @must_support.test_id, section.markdown) if @must_support && !section.empty?
      end

      # deep_stringify_keys writes string keys, and rebuilds hashes that entries
      # share so the YAML has no aliases.
      def write_trace_file(base_output_dir)
        path = File.join(base_output_dir, Generator::Naming.snake_case_for_profile(@group), FILE_NAME)
        FileUtils.mkdir_p(File.dirname(path))
        entries = @entries.map { |entry| entry.merge(tested_by: tested_by(entry)) }
        File.write(path, YAML.dump({ entries: }.deep_stringify_keys))
      end

      # The ids of the tests whose descriptions list the entry: the one that
      # makes its request, and the Must Support test when its items read an
      # element that test checks.
      def tested_by(entry)
        checks = @must_support && !ElementReads.new([entry], @group).list(checked: true).empty?
        [@destinations[entry]&.test_id, (@must_support.test_id if checks)].compact
      end
    end
  end
end
