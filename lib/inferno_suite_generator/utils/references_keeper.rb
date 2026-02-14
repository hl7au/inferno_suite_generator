# frozen_string_literal: true

module InfernoSuiteGenerator
  # Tracks resource references (e.g. Patient/test_patient) per URL. One instance per URL;
  # use .get_instance(url) to find the keeper for a given URL.
  class ReferencesKeeper
    attr_reader :references, :url

    class << self
      def entities
        @entities ||= []
      end

      def get_or_create_instance(url)
        get_instance(url) || new(url)
      end

      def get_instance(url)
        entities.find { |entity| entity.url == url }
      end
    end

    def initialize(url, references = {})
      @url = url
      @references = references
      self.class.entities << self
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
  end
end
