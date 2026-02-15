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
    cs_resources&.select { |resource| CSRESTResourceDecorator.new(resource).interaction_supported?(interaction) }
  end
end

# Decorator for an individual CapabilityStatement Rest resource.
# Provides helper methods for checking the supported interactions on the resource.
class CSRESTResourceDecorator
  attr_reader :rest_resource

  def initialize(rest_resource)
    @rest_resource = rest_resource
  end

  def interaction_supported?(interaction)
    rest_resource.interaction&.any? { |interact| interact.code == interaction }
  end
end
