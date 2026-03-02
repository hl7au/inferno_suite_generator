# frozen_string_literal: true

require_relative "constants"

module InfernoSuiteGenerator
  class Generator
    class GeneratorConfigKeeper
      # Provides utility methods for handling configuration values in the generator
      module Utils
        include Constants

        def get(path, default = nil)
          # TODO: Remove
          @config.dig(*path.split(".")) || default
        end

        def get_new(path, default = nil)
          @config.dig(*path.split("&.")) || default
        end

        def resolve_profile_resource_value(profile_path, resource_path, default_value = nil)
          profile_value = get_new(profile_path, default_value)
          resolved_profile_value = resolve_from_constants(profile_value)

          return resolved_profile_value || default_value if simple_type?(default_value)
          return resolved_profile_value if collection_with_elements?(resolved_profile_value)

          resource_value = get_new(resource_path, default_value)
          resolve_from_constants(resource_value)
        end

        def resolve_from_constants(value)
          constants[value] || value
        end

        def constants
          get("constants", Constants::EMPTY_HASH)
        end

        def simple_type?(value)
          value.is_a?(String) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
        end

        def collection_with_elements?(value)
          value.respond_to?(:any?) && value.any?
        end

        def resolve_value(profile, resource_type, attribute, default_value = nil)
          attribute_path = attribute.to_s.split(".").join("&.")
          profile_string = "configs&.profiles&.#{profile}&.#{attribute_path}"
          resource_string = "configs&.resources&.#{resource_type}&.#{attribute_path}"
          resolve_profile_resource_value(profile_string, resource_string, default_value)
        end

        def first_class_read?(profile_url, resource_type)
          resolve_value(profile_url, resource_type, "first_class_profile", "") == "read"
        end
      end
    end
  end
end
