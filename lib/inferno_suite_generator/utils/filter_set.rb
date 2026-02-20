# frozen_string_literal: true

module InfernoSuiteGenerator
  # Represents a single filter criterion consisting of a FHIRPath expression and an expected value.
  # Used to determine whether a given FHIR resource conforms to a specific filter condition.
  class FilterSetEntity
    def initialize(filter)
      @expression = filter["expression"]
      @value = filter["value"]
    end

    def conform_to_filter?(resource)
      evaluate_fhirpath_first_or_nil(resource, @expression) == @value
    end

    private

    def evaluate_fhirpath_first_or_nil(resource, path)
      evaluate_fhirpath(resource:, path:).map { |result| result["element"] }.first
    end
  end

  # The FilterSet class evaluates whether FHIR resources match complex filtering criteria.
  #
  # It represents a set of filters, where each filter is an array of AND conditions
  # (expression/value pairs), and multiple such filters are combined with OR logic.
  # A resource is considered to conform to the FilterSet if it satisfies at least
  # one set of AND conditions (i.e., at least one OR group is fully true).
  #
  # Example filter_set argument structure:
  # [
  #   [ { "expression" => FHIRPath, "value" => value } ],
  #   [ { "expression" => FHIRPath, "value" => value }, ... ]
  # ]
  class FilterSet
    def initialize(filter_set)
      @filter_set = filter_set
    end

    def filter_resources(resources)
      resources.select { |resource| conform_to_filter_set?(resource) }
    end

    private

    def conform_to_filter_set?(resource)
      @filter_set.each do |or_conditions|
        return true if all_conditions_true?(or_conditions, resource)
      end
      false
    end

    # :reek:UtilityFunction
    def all_conditions_true?(conditions, resource)
      conditions.all? do |cond_entity|
        FilterSetEntity.new(cond_entity).conform_to_filter?(resource)
      end
    end
  end
end
