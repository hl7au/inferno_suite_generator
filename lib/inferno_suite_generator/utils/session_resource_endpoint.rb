# frozen_string_literal: true

require "inferno/dsl/suite_endpoint"
require_relative "session_resource_finder"
require_relative "fhirpath_lab_cors"

module InfernoSuiteGenerator
  # `Inferno::DSL::SuiteEndpoint#handle` always looks up a *waiting* test run
  # via `test_run_identifier` before calling `make_response`, halting with a
  # 500 if none is found. That machinery exists for the "pause a test until
  # an external callback arrives" pattern (e.g. OAuth redirects); the endpoint
  # below is a plain session-scoped read and isn't tied to any waiting test,
  # so skip it.
  module StatelessSuiteEndpoint
    def handle(req, res)
      @req = req
      @res = res
      make_response
    rescue StandardError => e
      halt 500, e.full_message
    end

    def persist_request?
      false
    end
  end

  # Serves a resource the session received from the server under test, at
  # `/custom/<suite_id>/resources/:session_id/:resource_type/:resource_id`
  # (registered via `suite_endpoint` in the generated suite class), so
  # FHIRPath Lab can load it.
  class FetchResourceEndpoint < Inferno::DSL::SuiteEndpoint
    include StatelessSuiteEndpoint

    def make_response
      resource_json = session_resource

      if resource_json
        response.status = 200
        response.format = :json
        response.body = resource_json
      else
        response.status = 404
      end
    end

    def session_resource_finder
      @session_resource_finder ||= InfernoSuiteGenerator::SessionResourceFinder.new
    end

    private

    def session_resource
      session_resource_finder.find(
        session_id: request.params[:session_id],
        resource_type: request.params[:resource_type],
        resource_id: request.params[:resource_id]
      )
    end
  end
end
