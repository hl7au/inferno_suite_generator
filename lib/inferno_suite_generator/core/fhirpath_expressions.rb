# frozen_string_literal: true

require "fhirpath"
require "fhir_models"

module InfernoSuiteGenerator
  class Generator
    # Central store for FHIRPath expressions that are compiled once (parsed into a
    # reusable callable) and shared across the generator.
    module FhirpathExpressions
      module_function

      EXPECTATION_EXTENSION_URL =
        "http://hl7.org/fhir/StructureDefinition/capabilitystatement-expectation"

      def declared_profiles
        @declared_profiles ||= Fhirpath.compile_as_array(
          "(supportedProfile | profile).distinct()",
          FHIR::CapabilityStatement::Rest::Resource,
          String
        )
      end

      def cs_search_params
        @cs_search_params ||= Fhirpath.compile_as_array(
          "searchParam",
          FHIR::CapabilityStatement::Rest::Resource,
          FHIR::CapabilityStatement::Rest::Resource::SearchParam
        )
      end

      # Works for any FHIR element that carries the conformance-expectation extension
      # (a CapabilityStatement searchParam entry or a search-parameter-combination extension).
      def search_param_expectation
        @search_param_expectation ||= Fhirpath.compile_as_first(
          "extension.where(url = '#{EXPECTATION_EXTENSION_URL}').valueCode",
          FHIR::Model,
          String
        )
      end
    end
  end
end
