# frozen_string_literal: true

require "fhirpath"
require "fhir_models"

module InfernoSuiteGenerator
  class Generator
    # Central store for FHIRPath expressions. Each `compile_array` / `compile_first`
    # line declares a module method (`FhirpathExpressions.<name>`) that returns the
    # fhirpath-rb callable, parsed once on first use and memoised thereafter. The
    # raw expression strings live in the `EXPR` module so every path is declared
    # in one place and referenced by name.
    module FhirpathExpressions
      CS_REST_RESOURCE = FHIR::CapabilityStatement::Rest::Resource
      EXPECTATION_EXTENSION_URL =
        "http://hl7.org/fhir/StructureDefinition/capabilitystatement-expectation"
      SEARCH_PARAM_COMBINATION_EXTENSION_URL =
        "http://hl7.org/fhir/StructureDefinition/capabilitystatement-search-parameter-combination"

      # FHIRPath expression strings, one constant per expression.
      module EXPR
        DECLARED_PROFILES = "(supportedProfile | profile).distinct()"
        CS_SEARCH_PARAMS = "searchParam"
        CS_INTERACTIONS = "interaction"
        CS_OPERATIONS = "operation"
        CS_SEARCH_INCLUDES = "searchInclude"
        CS_SEARCH_REVINCLUDES = "searchRevInclude"
        CS_RESOURCES_SUPPORTING_INTERACTION =
          "rest.first().resource.where(interaction.code contains %code)"
        MANDATORY_ELEMENT_PATHS = "snapshot.element.where(min > 0).path"
        CODEABLE_CONCEPT_REQUIRED_BINDING_PATHS =
          "snapshot.element.where(type.code contains 'CodeableConcept' " \
          "and binding.strength = 'required').path"
        REFERENCE_ELEMENTS =
          "snapshot.element.where(type.first().code = 'Reference')"
        VALUE_SET_INLINE_CONCEPT_CODES = "compose.include.concept.code"
        VALUE_SET_LOOKUP_SYSTEM_URLS =
          "compose.include.where(concept.empty() and filter.empty()).system"
        VALUE_SET_INCLUDED_VALUE_SET_URLS =
          "compose.include.where(concept.empty() and (system.empty() or filter.exists())).valueSet"
        CODE_SYSTEM_CONCEPT_CODES = "concept.code"
        SEARCH_PARAM_COMBINATIONS =
          "extension.where(url = '#{SEARCH_PARAM_COMBINATION_EXTENSION_URL}')".freeze
        SEARCH_PARAM_COMBINATION_NAMES = "extension.valueString"
        SEARCH_PARAM_EXPECTATION =
          "extension.where(url = '#{EXPECTATION_EXTENSION_URL}').valueCode".freeze
      end

      class << self
        private

        def compile_array(name, *)
          callable = nil
          define_singleton_method(name) { callable ||= Fhirpath.compile_as_array(*) }
        end

        def compile_first(name, *)
          callable = nil
          define_singleton_method(name) { callable ||= Fhirpath.compile_as_first(*) }
        end
      end

      compile_array :declared_profiles, EXPR::DECLARED_PROFILES, CS_REST_RESOURCE, String
      compile_array :cs_search_params, EXPR::CS_SEARCH_PARAMS, CS_REST_RESOURCE, CS_REST_RESOURCE::SearchParam
      compile_array :cs_interactions, EXPR::CS_INTERACTIONS, CS_REST_RESOURCE, CS_REST_RESOURCE::Interaction
      compile_array :cs_operations, EXPR::CS_OPERATIONS, CS_REST_RESOURCE, CS_REST_RESOURCE::Operation
      compile_array :cs_search_includes, EXPR::CS_SEARCH_INCLUDES, CS_REST_RESOURCE, String
      compile_array :cs_search_revincludes, EXPR::CS_SEARCH_REVINCLUDES, CS_REST_RESOURCE, String
      compile_array :cs_resources_supporting_interaction, EXPR::CS_RESOURCES_SUPPORTING_INTERACTION,
                    FHIR::CapabilityStatement, CS_REST_RESOURCE
      compile_array :mandatory_element_paths, EXPR::MANDATORY_ELEMENT_PATHS, FHIR::StructureDefinition, String
      compile_array :codeable_concept_required_binding_paths, EXPR::CODEABLE_CONCEPT_REQUIRED_BINDING_PATHS,
                    FHIR::StructureDefinition, String
      compile_array :reference_elements, EXPR::REFERENCE_ELEMENTS, FHIR::StructureDefinition, FHIR::ElementDefinition
      compile_array :value_set_inline_concept_codes, EXPR::VALUE_SET_INLINE_CONCEPT_CODES, FHIR::ValueSet, String
      compile_array :value_set_lookup_system_urls, EXPR::VALUE_SET_LOOKUP_SYSTEM_URLS, FHIR::ValueSet, String
      compile_array :value_set_included_value_set_urls, EXPR::VALUE_SET_INCLUDED_VALUE_SET_URLS, FHIR::ValueSet, String
      compile_array :code_system_concept_codes, EXPR::CODE_SYSTEM_CONCEPT_CODES, FHIR::CodeSystem, String
      compile_array :search_param_combinations, EXPR::SEARCH_PARAM_COMBINATIONS, CS_REST_RESOURCE, FHIR::Extension
      compile_array :search_param_combination_names, EXPR::SEARCH_PARAM_COMBINATION_NAMES, FHIR::Extension, String
      compile_first :search_param_expectation, EXPR::SEARCH_PARAM_EXPECTATION, FHIR::Model, String
    end
  end
end
