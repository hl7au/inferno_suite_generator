# frozen_string_literal: true

require "inferno/dsl/suite_endpoint"
require_relative "kept_resources_repository"

module InfernoSuiteGenerator
  # `Inferno::DSL::SuiteEndpoint#handle` always looks up a *waiting* test run
  # via `test_run_identifier` before calling `make_response`, halting with a
  # 500 if none is found. That machinery exists for the "pause a test until
  # an external callback arrives" pattern (e.g. OAuth redirects); the
  # resource-keeper endpoints below are plain session-scoped CRUD against
  # `KeptResourcesRepository` and aren't tied to any waiting test, so skip it.
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

    def kept_resources_repository
      @kept_resources_repository ||= InfernoSuiteGenerator::KeptResourcesRepository.new
    end
  end

  # Custom suite endpoints (registered via `suite_endpoint` in the generated
  # suite class) exposing the in-process resource keeper at
  # `/custom/<suite_id>/resources/...`. These replace the external
  # inferno_resources_keeper service.

  # Fetches a resource previously saved via KeptResourcesRepository#save
  # (called directly from test runtime, not over HTTP).
  class FetchResourceEndpoint < Inferno::DSL::SuiteEndpoint
    include StatelessSuiteEndpoint

    def make_response
      record = kept_resource

      if record
        response.status = 200
        response.format = :json
        response.body = record[:resource_json]
      else
        response.status = 404
      end
    end

    private

    def kept_resource
      kept_resources_repository.find(
        session_id: request.params[:session_id],
        resource_type: request.params[:resource_type],
        resource_id: request.params[:resource_id]
      )
    end
  end

  # Deletes all resources kept for a session (e.g. once a test run ends).
  class DeleteSessionResourcesEndpoint < Inferno::DSL::SuiteEndpoint
    include StatelessSuiteEndpoint

    def make_response
      kept_resources_repository.delete_session(session_id: request.params[:session_id])
      response.status = 204
    end
  end
end
