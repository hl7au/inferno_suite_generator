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

      # Snapshot element paths that are mandatory (min cardinality > 0).
      def mandatory_element_paths
        @mandatory_element_paths ||= Fhirpath.compile_as_array(
          "snapshot.element.where(min > 0).path",
          FHIR::StructureDefinition,
          String
        )
      end

      # Snapshot element paths that have a CodeableConcept type and a required binding.
      def codeable_concept_required_binding_paths
        @codeable_concept_required_binding_paths ||= Fhirpath.compile_as_array(
          "snapshot.element.where(type.code contains 'CodeableConcept' and binding.strength = 'required').path",
          FHIR::StructureDefinition,
          String
        )
      end

      # Snapshot elements whose (first) type is a Reference.
      def reference_elements
        @reference_elements ||= Fhirpath.compile_as_array(
          "snapshot.element.where(type.first().code = 'Reference')",
          FHIR::StructureDefinition,
          FHIR::ElementDefinition
        )
      end

      # Codes listed inline in a ValueSet's `compose.include` entries.
      def value_set_inline_concept_codes
        @value_set_inline_concept_codes ||= Fhirpath.compile_as_array(
          "compose.include.concept.code",
          FHIR::ValueSet,
          String
        )
      end

      # `compose.include` system URLs whose codes must be pulled from the referenced
      # CodeSystem — i.e. the include names a system, lists no inline concepts, and
      # applies no filter (an intensional filter can't be expanded here).
      def value_set_lookup_system_urls
        @value_set_lookup_system_urls ||= Fhirpath.compile_as_array(
          "compose.include.where(concept.empty() and filter.empty()).system",
          FHIR::ValueSet,
          String
        )
      end

      # `compose.include` nested ValueSet URLs to expand recursively (the include
      # neither lists inline concepts nor resolves to a plain system reference).
      def value_set_included_value_set_urls
        @value_set_included_value_set_urls ||= Fhirpath.compile_as_array(
          "compose.include.where(concept.empty() and (system.empty() or filter.exists())).valueSet",
          FHIR::ValueSet,
          String
        )
      end

      # The (top-level) concept codes defined by a CodeSystem.
      def code_system_concept_codes
        @code_system_concept_codes ||= Fhirpath.compile_as_array(
          "concept.code",
          FHIR::CodeSystem,
          String
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
