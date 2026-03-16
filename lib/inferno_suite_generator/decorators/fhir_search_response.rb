# frozen_string_literal: true

# Handles the response from a FHIR search operation, providing
# utility methods to parse the response body as a FHIR::Bundle if the response
# was successful.
#
# @example
#   response = FHIRSearchResponse.new(fhir_request)
#   bundle = response.to_bundle
#
class FHIRSearchResponse
  # HTTP status code indicating a successful search response.
  SUCCESS_RESPONSE_STATUS = 200

  # @return [Integer] the HTTP response status code
  attr_reader :status
  # @return [Boolean] whether the response status indicates success
  attr_reader :success
  # @return [String, nil] the response body in JSON format, or nil if absent
  attr_reader :response_body

  # Initializes a new FHIRSearchResponse.
  #
  # @param fhir_request [Object] The FHIR request object, expected to respond to
  #   #status (Integer) and #response_body (String or nil).
  def initialize(fhir_request)
    request_status = fhir_request.status
    @status = request_status
    @success = request_status == SUCCESS_RESPONSE_STATUS
    @response_body = fhir_request.response_body
  end

  # Parses the response body as a FHIR::Bundle if the response is successful and
  # the body is present. If the response is not successful or the body is absent,
  # returns nil.
  #
  # @return [FHIR::Bundle, nil] The parsed FHIR::Bundle, or nil if the response was
  #   not successful or the body is absent.
  def to_bundle
    return nil unless success
    return nil unless response_body

    FHIR.from_contents(response_body)
  end
end
