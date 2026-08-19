# frozen_string_literal: true

require "net/http"
require "json"

module InfernoSuiteGenerator
  # Sends fetched FHIR resources to an external inferno_resources_keeper service
  # (https://github.com/projkov/inferno_resources_keeper) for later retrieval,
  # keyed by the Inferno test session id.
  #
  # Failures (network errors, non-2xx responses) are swallowed: the keeper is an
  # auxiliary side-channel and must never fail or stall the actual conformance tests.
  class ResourceKeeperClient
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 2

    attr_reader :base_url

    def initialize(base_url)
      @base_url = base_url
    end

    def save(session_id:, resource:)
      return false if base_url.blank? || session_id.blank? || resource.nil?

      response = post(payload(session_id, resource))
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    private

    def payload(session_id, resource)
      {
        sessionId: session_id,
        resourceType: resource.resourceType,
        resourceId: resource.id,
        resource: resource.to_hash
      }.to_json
    end

    def post(body)
      uri = URI.join(base_url, "/resources")

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT,
                                          read_timeout: READ_TIMEOUT) do |http|
        request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
        request.body = body
        http.request(request)
      end
    end
  end
end
