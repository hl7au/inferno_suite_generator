# frozen_string_literal: true

module InfernoSuiteGenerator
  # Registry of message formats that `FhirpathLabMessageLinker` knows how to parse.
  #
  # To support a new validator's message format, add a new `Regexp` to `PATTERNS`.
  # It must define the same named captures as the existing entries
  # (`resource_type`, `resource_id`, `path`, `detail`, and optionally `echo`) so
  # `FhirpathLabMessageLinker#linkify` can use whichever pattern matched without
  # caring which one it was. Patterns are tried in order; the first match wins.
  module FhirpathLabMessagePatterns
    # Some validators (e.g. the Java validator's terminology errors) repeat the
    # resource type as its own segment before the path:
    #   "Patient/pat-sf: Patient: Patient.extension[0]: Internal validator error..."
    # while others go straight from the id to the path:
    #   "Patient/123: Patient.name[0].given: Minimum required = 1, but only found 0"
    # The middle `echo` segment is optional and, when present, must repeat
    # `resource_type` exactly — that's what distinguishes it from a path that
    # genuinely starts with the bare resource type (e.g. a root-level issue).
    #
    # `path` allows colons (a FHIRPath expression may embed one, e.g. a URL in
    # `system='http://...'`), stopping only at the specific ": " sequence that
    # separates it from `detail`.
    JAVA_VALIDATOR_PATTERN = %r{
      \A
      (?<resource_type>[A-Za-z][A-Za-z0-9]*)/(?<resource_id>[^\s:]+):\x20
      (?:(?<echo>\k<resource_type>):\x20)?
      (?<path>(?:(?!:\x20)[^\n])+):\x20
      (?<detail>.*)
      \z
    }mx

    PATTERNS = [
      JAVA_VALIDATOR_PATTERN
    ].freeze

    REQUIRED_CAPTURES = %w[resource_type resource_id path detail].freeze

    module_function

    def match(message)
      PATTERNS.each do |pattern|
        result = pattern.match(message)
        return result if result
      end

      nil
    end
  end
end
