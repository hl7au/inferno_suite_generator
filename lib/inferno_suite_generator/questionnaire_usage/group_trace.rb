# frozen_string_literal: true

require "active_support/core_ext/hash/keys"
require "fileutils"
require "yaml"
require_relative "../utils/naming"
require_relative "element_reads"
require_relative "group_summary"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Writes one group's Delivery::Placements: its Must Support section, its
    # trace file and its summary.
    class GroupTrace
      FILE_NAME = "questionnaire_usage.yml"

      def initialize(group, placements)
        @group = group
        @placements = placements
      end

      def write(descriptions, base_output_dir)
        write_must_support(descriptions)
        write_trace_file(base_output_dir)
        summary = GroupSummary.new(@group, @placements)
        descriptions.group(@group, summary.markdown) unless summary.empty?
      end

      private

      def write_must_support(descriptions)
        test = @placements.filter_map(&:must_support).first
        section = MustSupportSection.new(@placements, @group)
        descriptions.test(@group, test.test_id, section.markdown) if test && !section.empty?
      end

      # deep_stringify_keys writes string keys, and rebuilds hashes that entries
      # share so the YAML has no aliases.
      def write_trace_file(base_output_dir)
        path = File.join(base_output_dir, Generator::Naming.snake_case_for_profile(@group), FILE_NAME)
        FileUtils.mkdir_p(File.dirname(path))
        entries = @placements.map { |placement| placement.entry.to_h.merge(tested_by: placement.tests.map(&:test_id)) }
        File.write(path, YAML.dump({ entries: }.deep_stringify_keys))
      end
    end
  end
end
