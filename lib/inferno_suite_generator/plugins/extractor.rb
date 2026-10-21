# frozen_string_literal: true

module InfernoSuiteGenerator
  module Plugins
    # Base class for a plugin's own data extraction, one instance per group. Subclasses implement extract,
    # which returns the plugin's data for group_metadata, or nil to leave that group out. The result of the
    # class method fits context.metadata.groups and Plugins::TestGenerator.generate:
    #
    #   data_by_group = MyExtractor.extract(context)   # => { group_metadata => { "interaction" => ... } }
    #   context.metadata.groups(data_by_group)
    class Extractor
      attr_reader :context, :group_metadata

      def self.extract(context)
        context.groups.to_h { |group_metadata| [group_metadata, new(context, group_metadata).extract] }.compact
      end

      def initialize(context, group_metadata)
        @context = context
        @group_metadata = group_metadata
      end

      def extract
        raise NotImplementedError, "#{self.class} must implement extract"
      end
    end
  end
end
