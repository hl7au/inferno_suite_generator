# frozen_string_literal: true

require "fhir_models"
require_relative "../core/fhirpath_expressions"

# Decorator for FHIR::R4::CapabilityStatement that provides additional
# utility methods for working with resource types and extracting values.
# Use the wrapped capability statement directly when you need standard accessors.
class CapabilityStatementDecorator
  attr_reader :capability_statement

  def initialize(capability_statement)
    @capability_statement = capability_statement
  end

  def get_resources_by_interaction(interaction)
    InfernoSuiteGenerator::Generator::FhirpathExpressions
      .cs_resources_supporting_interaction
      .call(capability_statement, { "code" => interaction })
  end
end
