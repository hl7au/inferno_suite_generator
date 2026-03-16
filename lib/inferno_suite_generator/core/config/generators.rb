# frozen_string_literal: true

require_relative "constants"
require_relative "utils"
require_relative "getters"
require_relative "../../utils/generic"

module InfernoSuiteGenerator
  class Generator
    class GeneratorConfigKeeper
      # Provides methods for generating test-specific configuration and inputs
      #
      # This module contains methods that generate configuration values and inputs
      # for various test types, including search tests, read tests, and special cases.
      module Generators
        include Constants
        include Utils
        include Getters
        include GenericUtils

        def custom_generators
          get_new("configs&.generic&.register_generators", EMPTY_ARRAY)
        end

        def resources_to_exclude(profile_url, resource_type)
          resolve_value(profile_url, resource_type, "skip", false)
        end

        def add_extra_searches?(profile_url, resource_type, search_names)
          filtered_extra_searches = extra_searches(profile_url, resource_type).select do |search|
            search["type"] == "search"
          end
          filtered_extra_searches.map { |search| search["params"] }.include?(search_names)
        end

        def exclude_resource_old?(resource_type)
          resources_configs.key?(resource_type) ? resources_configs[resource_type]["skip"] || false : false
        end

        def exclude_resource?(profile_url, resource_type)
          resolve_value(profile_url, resource_type, "skip", nil)
        end

        def specific_identifiers(profile_url, resource_type, param_id)
          resolve_value(profile_url, resource_type, "search_param.#{param_id}.extra_tests_with", EMPTY_ARRAY)
        end

        def get_executor(profile_url, resource, param_id)
          resolve_value(profile_url, resource, "override_executor.search.#{param_id}", "run_search_test")
        end

        def multiple_or_and_search_by_target_resource?(profile_url, resource_type, params)
          resolve_value(profile_url, resource_type, "search_multiple_or_and_by_target_resource", EMPTY_ARRAY) == params
        end

        def first_class_search?(profile_url, resource_type, search_params)
          resolve_value(profile_url, resource_type, "first_class_profile", "") == "search" && search_params == ["_id"]
        end

        def create_test_input_data(group_name, profile_name, default_value)
          test_input_builder("#{camel_to_snake(group_name)}_data", "#{profile_name} resource in JSON format",
                             "#{profile_name} in JSON format to be sent to the server.", default_value)
        end

        def read_test_ids_inputs(profile_url, resource_type)
          return unless first_class_read?(profile_url, resource_type)

          snake_case_resource_type = camel_to_snake(resource_type)
          description = "Comma separated list of #{snake_case_resource_type.tr("_", " ")} " \
                        "IDs that in sum contain all MUST SUPPORT elements"
          test_input_builder(
            "#{snake_case_resource_type}_ids", "#{resource_type} IDs",
            description, constants["read_ids.#{snake_case_resource_type}"] || ""
          )
        end

        def search_test_ids_inputs(profile_url, resource_type, param_names)
          return unless first_class_search?(profile_url, resource_type, param_names)

          snake_case_resource_type = camel_to_snake(resource_type)
          test_input_builder("#{snake_case_resource_type}_ids", "#{resource_type} IDs",
                             "Comma separated list of #{snake_case_resource_type.tr("_", " ")} " \
                             "IDs that in sum contain all MUST SUPPORT elements",
                             constants["read_ids.#{snake_case_resource_type}"] || "")
        end

        def test_medication_inclusion?(profile_url, resource_type)
          # NOTE: This attribute of the config should be changed for something generic
          resolve_value(profile_url, resource_type, "search.test_medication_inclusion")
        end

        def process_include_search(result, resource, search)
          include_parameter = "#{resource}:#{search["param"]}"
          result[include_parameter] = {
            "parameter" => include_parameter,
            "target_resource" => search["target_resource"],
            "paths" => search["paths"]
          }
          result
        end

        def special_includes_cases(profile_url, resource)
          result = EMPTY_HASH.dup

          extra_searches(profile_url, resource).select { |search| search["type"] == "include" }
                                               .each { |search| process_include_search(result, resource, search) }

          result
        end
      end
    end
  end
end
