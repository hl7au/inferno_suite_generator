# frozen_string_literal: true

require "fhir_models"

# Decorator for FHIR::R4::CapabilityStatement that provides additional
# utility methods for working with resource types and extracting values.
# Use the wrapped capability statement directly when you need standard accessors.
class CapabilityStatementDecorator
  attr_reader :capability_statement

  def initialize(capability_statement)
    @capability_statement = capability_statement
  end

  def get_resources_by_interaction(interaction)
    resources_by_interaction(interaction) || []
  end

  private

  def cs_resources
    @cs_resources ||= @capability_statement.rest&.first&.resource
  end

  def resources_by_interaction(interaction)
    cs_resources&.select do |resource|
      resource_interaction_correct?(resource, interaction)
    end
  end

  def resource_interaction_correct?(resource, interaction_code)
    resource.interaction&.any? { |interact| interact.code == interaction_code }
  end
end
