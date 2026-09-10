# frozen_string_literal: true

require "fhirpath"
require "fhir_models"

module InfernoSuiteGenerator
  class Generator
    # Central store for FHIRPath expressions that are compiled once (parsed into a
    # reusable callable) and shared across the generator.
    module FhirpathExpressions
      module_function

      CS_REST_RESOURCE = FHIR::CapabilityStatement::Rest::Resource
      EXPECTATION_EXTENSION_URL =
        "http://hl7.org/fhir/StructureDefinition/capabilitystatement-expectation"
      SEARCH_PARAM_COMBINATION_EXTENSION_URL =
        "http://hl7.org/fhir/StructureDefinition/capabilitystatement-search-parameter-combination"

      def declared_profiles
        @declared_profiles ||= Fhirpath.compile_as_array(
          "(supportedProfile | profile).distinct()",
          CS_REST_RESOURCE,
          String
        )
      end

      def cs_search_params
        @cs_search_params ||= Fhirpath.compile_as_array(
          "searchParam",
          CS_REST_RESOURCE,
          CS_REST_RESOURCE::SearchParam
        )
      end

      def cs_interactions
        @cs_interactions ||= Fhirpath.compile_as_array(
          "interaction",
          CS_REST_RESOURCE,
          CS_REST_RESOURCE::Interaction
        )
      end

      def cs_operations
        @cs_operations ||= Fhirpath.compile_as_array(
          "operation",
          CS_REST_RESOURCE,
          CS_REST_RESOURCE::Operation
        )
      end

      def cs_search_includes
        @cs_search_includes ||= Fhirpath.compile_as_array("searchInclude", CS_REST_RESOURCE, String)
      end

      def cs_search_revincludes
        @cs_search_revincludes ||= Fhirpath.compile_as_array("searchRevInclude", CS_REST_RESOURCE, String)
      end

      # The CapabilityStatement rest resources that support a given interaction code
      # (pass it as the `code` environment variable: `.call(capability_statement, { "code" => "search-type" })`).
      def cs_resources_supporting_interaction
        @cs_resources_supporting_interaction ||= Fhirpath.compile_as_array(
          "rest.first().resource.where(interaction.code contains %code)",
          FHIR::CapabilityStatement,
          CS_REST_RESOURCE
        )
      end

      # Works for any FHIR element that carries the conformance-expectation extension
      # (a CapabilityStatement interaction/operation/searchParam entry or a
      # search-parameter-combination extension).
      def search_param_expectation
        @search_param_expectation ||= Fhirpath.compile_as_first(
          "extension.where(url = '#{EXPECTATION_EXTENSION_URL}').valueCode",
          FHIR::Model,
          String
        )
      end

      # The search-parameter-combination extensions declared on a CapabilityStatement resource.
      def search_param_combinations
        @search_param_combinations ||= Fhirpath.compile_as_array(
          "extension.where(url = '#{SEARCH_PARAM_COMBINATION_EXTENSION_URL}')",
          CS_REST_RESOURCE,
          FHIR::Extension
        )
      end

      # The search parameter names bundled inside a single search-parameter-combination extension.
      def search_param_combination_names
        @search_param_combination_names ||= Fhirpath.compile_as_array(
          "extension.valueString",
          FHIR::Extension,
          String
        )
      end
    end
  end
end
