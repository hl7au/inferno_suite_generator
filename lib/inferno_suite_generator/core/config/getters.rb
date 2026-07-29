# frozen_string_literal: true

require_relative "constants"
require_relative "utils"
require_relative "../../patch_checks"

module InfernoSuiteGenerator
  class Generator
    class GeneratorConfigKeeper
      # Provides getter methods for accessing configuration values
      #
      # This module contains methods for retrieving various configuration settings
      # from the GeneratorConfigKeeper's configuration object.
      module Getters
        include Constants
        include Utils

        def tx_server_url
          get("suite.tx_server_url")
        end

        def resources_configs
          get("configs.resources", EMPTY_HASH)
        end

        def ig_link
          get("ig.link")
        end

        def ig_name
          get("ig.name")
        end

        def cs_profile_url
          get("ig.cs_profile_url")
        end

        def cs_version_specific_url
          get("ig.cs_version_specific_url")
        end

        def id
          get("ig.id")
        end

        def title
          get("suite.title")
        end

        def default_fhir_server
          get("constants.default_fhir_server")
        end

        def links
          get("suite.links", EMPTY_ARRAY)
        end

        def package_archive_path
          get("ig.package_archive_path", nil)
        end

        def extra_json_paths
          get("suite.extra_json_paths", EMPTY_ARRAY)
        end

        def search_params_to_ignore
          get("configs.generic.search_params_to_ignore", EMPTY_ARRAY)
        end

        def patch_checks
          get("configs.generic.patch_checks", InfernoSuiteGenerator::PATCH_CHECKS)
        end

        def validation_message_exclusions
          get("configs.generic.validation_message_exclusions", EMPTY_ARRAY)
        end

        def validation_message_level_overrides
          get("configs.generic.validation_message_level_overrides", EMPTY_ARRAY)
        end

        def search_params_expectation
          get("configs.generic.expectation", EMPTY_ARRAY)
        end

        def outer_groups
          get("suite.outer_groups", EMPTY_ARRAY)
        end

        def extra_imports
          get("suite.extra_imports", EMPTY_ARRAY)
        end

        def rewrite_profile_url
          get("configs.generic.rewrite_profile_url", EMPTY_HASH)
        end

        def extra_searches(profile_url, resource_type)
          resolve_value(profile_url, resource_type, "extra_searches", EMPTY_ARRAY)
        end

        def resource_to_create_filter(profile_url, resource_type)
          resolve_value(profile_url, resource_type, "resources_to_create_filter")
        end

        def create_resource_overrides(profile_url, resource_type)
          resolve_value(profile_url, resource_type, "create_resource_overrides", EMPTY_HASH)
        end

        def fixed_values_to_search(profile_url, resource_type)
          resolve_value(profile_url, resource_type, "fixed_values_to_search", EMPTY_ARRAY)
        end

        def rewrite_igs
          get("suite.rewrite_igs")
        end
      end
    end
  end
end
