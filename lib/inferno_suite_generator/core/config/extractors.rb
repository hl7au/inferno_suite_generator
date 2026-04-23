# frozen_string_literal: true

require_relative "constants"
require_relative "utils"

module InfernoSuiteGenerator
  class Generator
    class GeneratorConfigKeeper
      # Provides methods for extracting specific configuration values for test generation
      #
      # This module contains methods that extract and process configuration values
      # related to search parameters, expectations, and other test-specific settings.
      module Extractors
        include Constants
        include Utils

        def multiple_and_expectation(profile_url, resource_type, param_id)
          resolve_value(profile_url, resource_type, "search_param.#{param_id}.multiple_and_expectation")
        end

        def multiple_or_expectation(profile_url, resource_type, param_id)
          resolve_value(profile_url, resource_type, "search_param.#{param_id}.multiple_or_expectation")
        end

        def override_search_expectation(profile_url, resource_type, param_id)
          resolve_value(profile_url, resource_type, "search_param.#{param_id}.expectation_change")
        end

        def fixed_search_values(profile_url, resource_type, param_id)
          resolve_value(profile_url, resource_type, "search_param.#{param_id}.default_values", EMPTY_ARRAY)
        end

        def skip_metadata_extraction?(profile_url, resource_type)
          resolve_value(profile_url, resource_type, "skip", false)
        end

        def must_support_remove_elements(profile_url, resource)
          resolve_value(profile_url, resource, "must_support.remove_elements", EMPTY_ARRAY)
        end

        def get_comparators(profile_url, resource_type, param_id)
          resolve_value(profile_url, resource_type, "search_param.#{param_id}.comparators", EMPTY_ARRAY)
        end

        def get_first_class_status(profile_url, resource)
          resolve_value(profile_url, resource, "first_class_profile", false)
        end

        def get_forced_initial_search(profile_url, resource)
          resolve_value(profile_url, resource, "forced_initial_search", EMPTY_ARRAY)
        end

        def keep_all_search_results(profile_url, resource)
          resolve_value(profile_url, resource, "keep_all_search_results", false)
        end

        def first_search_params(profile_url, resource)
          is_first_class = get_first_class_status(profile_url, resource)
          forced_initial_search = get_forced_initial_search(profile_url, resource)
          default_value = ["patient"]

          return ["_id"] if is_first_class
          return forced_initial_search if forced_initial_search.any?

          default_value
        end

        def custom_extractors(profile_url, resource)
          resolve_value(profile_url, resource, "register_extractors", EMPTY_ARRAY)
        end

        def filter_set(profile_url, resource_type)
          resolve_value(profile_url, resource_type, "filter_set", EMPTY_ARRAY)
        end

        def elements_to_exclude(profile_url, resource)
          resolve_value(profile_url, resource, "exclude_elements_from_must_support", EMPTY_ARRAY)
        end

        def slices_to_exclude(profile_url, resource)
          resolve_value(profile_url, resource, "exclude_slices_from_must_support", EMPTY_ARRAY)
        end

        def slice_discriminator_default_values(profile_url, resource)
          resolve_value(profile_url, resource, "slice_discriminator_default_value", EMPTY_ARRAY)
        end
      end
    end
  end
end
