# frozen_string_literal: true

require_relative "../core/config/utils"

# GetterEntity is a helper class that encapsulates information needed to resolve a configuration value,
# based on a profile URL, resource type, a config path, and a default value. It provides a method
# for resolving the value with correct fallback logic (profile-specific, then resource-specific, then default).
class GetterEntity
  include InfernoSuiteGenerator::Generator::GeneratorConfigKeeper::Utils

  def initialize(profile_url, resource_type, path, default_value = nil)
    @profile_url = profile_url
    @resource_type = resource_type
    @path = path
    @default_value = default_value
  end

  def resolve_value
    resolve_profile_resource_value(
      "configs&.profiles&.#{@profile_url}&.#{@path}",
      "configs&.resources&.#{@resource_type}&.#{@path}",
      @default_value
    )
  end
end
