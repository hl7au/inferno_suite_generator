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

      def destroy_instance(url)
        entities.delete(get_instance(url))
      end
    end

    def initialize(url, references = {})
      @url = url
      @references = references
      self.class.entities << self
    end

    def add_reference(reference)
      resource_type, resource_id = reference.split("/", 2)
      @references[resource_type] = (@references[resource_type] || []) + [resource_id]
    end

    def add_references(references)
      references.each { |reference| add_reference(reference) }
    end

    def references_for_resource_type(resource_type)
      (@references[resource_type] || []).reverse
    end

    def add_references_from_bundle(bundle)
      refs = bundle.entry.map(&:resource).map { |res| self.class.reference_string_for(res) }
      add_references(refs)
    end

    def self.reference_string_for(resource)
      "#{resource.resourceType}/#{resource.id}"
    end

    def add_references_from_input(input)
      add_references(JSON.parse(input))
    end
  end
end
