# frozen_string_literal: true

require "active_support/core_ext/hash/keys"
require "fileutils"
require "yaml"
require_relative "../utils/naming"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Writes each traced group's entries to its trace file, each with the ids of
    # the tests a Delivery decided list it as `tested_by`.
    class TraceFiles
      FILE_NAME = "questionnaire_usage.yml"

      def initialize(delivery)
        @delivery = delivery
      end

      def write(base_output_dir)
        @delivery.each_group { |group, placements| write_file(base_output_dir, group, placements) }
      end

      private

      # deep_stringify_keys writes string keys, and rebuilds hashes that entries
      # share so the YAML has no aliases.
      # :reek:UtilityFunction
      def write_file(base_output_dir, group, placements)
        path = File.join(base_output_dir, Generator::Naming.snake_case_for_profile(group), FILE_NAME)
        FileUtils.mkdir_p(File.dirname(path))
        entries = placements.map { |placement| placement.entry.to_h.merge(tested_by: placement.tests.map(&:test_id)) }
        File.write(path, YAML.dump({ entries: }.deep_stringify_keys))
      end
    end
  end
end
