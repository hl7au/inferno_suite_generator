# frozen_string_literal: true

require_relative "constants"
require_relative "dynamic_value_resolver"

module InfernoSuiteGenerator
  class Generator
    class GeneratorConfigKeeper
      # Provides utility methods for handling configuration values in the generator
      module Utils
        include Constants
        include DynamicValueResolver

        def get(path, default = nil)
          # TODO: Remove
          @config.dig(*path.split(".")) || default
        end

        def get_new(path, default = nil)
          @config.dig(*path.split("&.")) || default
        end

        def resolve_profile_resource_value(profile_path, resource_path, default_value = nil)
          profile_value = resolve_raw(profile_path)
          return profile_value if profile_value

          resource_value = resolve_raw(resource_path)
          return resource_value if resource_value

          default_value
        end

        def resolve_raw(value_path)
          value = get_new(value_path)
          resolve_from_constants(value)
        end

        def resolve_from_constants(value)
          value_to_resolve = constants[value] || value
          resolve_dynamic_values(value_to_resolve)
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
