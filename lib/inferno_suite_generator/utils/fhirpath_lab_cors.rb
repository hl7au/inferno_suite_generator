# frozen_string_literal: true

require "uri"

module InfernoSuiteGenerator
  # Rack wrapper that lets the FHIRPath Lab origin read a kept resource
  # cross-origin: FHIRPath Lab fetches the `resource=` URL from the browser.
  class FhirpathLabCors
    # `Cache-Control` is not CORS-safelisted, so FHIRPath Lab's GET is preflighted.
    PREFLIGHT_HEADERS = {
      "Access-Control-Allow-Methods" => "GET",
      "Access-Control-Allow-Headers" => "Accept, Cache-Control",
      "Access-Control-Max-Age" => "600"
    }.freeze

    def self.origin_of(url)
      uri = URI.parse(url.to_s.strip)
      uri.is_a?(URI::HTTP) && uri.host ? uri.normalize.origin : nil
    rescue URI::InvalidURIError
      nil
    end

    def initialize(app, lab_url:)
      @app = app
      @allowed_origin = self.class.origin_of(lab_url)
    end

    def call(env)
      return preflight(env) if env["REQUEST_METHOD"] == "OPTIONS"

      status, headers, body = @app.call(env)
      [status, headers.merge(cors_headers(env)), body]
    end

    private

    def preflight(env)
      headers = cors_headers(env)
      headers = headers.merge(PREFLIGHT_HEADERS) if origin_allowed?(env)
      [204, headers, []]
    end

    def cors_headers(env)
      headers = { "Vary" => "Origin" }
      headers["Access-Control-Allow-Origin"] = @allowed_origin if origin_allowed?(env)
      headers
    end

    def origin_allowed?(env)
      @allowed_origin ? env["HTTP_ORIGIN"] == @allowed_origin : false
    end
  end
end
