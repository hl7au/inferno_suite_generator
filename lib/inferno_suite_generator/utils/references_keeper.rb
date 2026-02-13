# frozen_string_literal: true

require "singleton"

module InfernoSuiteGenerator
  # This class is used to keep track of the references that need to be set for the resources.
  # Pay attention that this class is keeping value for the reference like Patient/test_patient.
  class ReferencesKeeper
    include Singleton

    attr_reader :references

    class << self
      def instance(references = nil)
        super().tap do |keeper|
          keeper.send(:refs, references) if references
        end
      end
    end

    def initialize
      @references = {}
    end

    def add_reference(reference)
      resource_type, resource_id = reference.split("/", 2)

      @references[resource_type] ||= []
      @references[resource_type] << resource_id
      @references[resource_type].uniq!
    end

    def add_references(references)
      references.each { |reference| add_reference(reference) }
    end

    def references_for_resource_type(resource_type)
      @references[resource_type] || []
    end

    private

    def refs(references)
      @references = references
    end
  end
end
