# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # The trace entries of every questionnaire, each with the groups its source links to, which share it.
    class Trace
      def initialize
        @entries = {}
        @groups = {}.compare_by_identity
      end

      # Links the entry to the groups; adding it again links more groups. Returns the Trace.
      def add(groups, entry)
        linked = (@groups[entry] ||= [])
        (groups - linked).each do |group|
          linked << group
          (@entries[group.profile_url] ||= []) << entry
        end
        self
      end

      # The entries of the group's profile, in trace order.
      def entries(group)
        @entries.fetch(group.profile_url) { [] }
      end

      # The groups that share the entry, in the order they were linked.
      def groups(entry)
        @groups.fetch(entry) { [] }
      end

      # `{ profile_url => [TraceEntry] }`, in trace order.
      def to_h
        @entries.transform_values(&:dup)
      end
    end
  end
end
