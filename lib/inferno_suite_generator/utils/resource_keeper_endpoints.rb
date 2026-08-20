# frozen_string_literal: true

require "inferno/dsl/suite_endpoint"
require_relative "kept_resources_repository"

module InfernoSuiteGenerator
  # Custom suite endpoints (registered via `suite_endpoint` in the generated
  # suite class) exposing the in-process resource keeper at
  # `/custom/<suite_id>/resources/...`. These replace the external
  # inferno_resources_keeper service.
  class SaveResourceEndpoint < Inferno::DSL::SuiteEndpoint
    def make_response
      save_resource
      response.status = 204
    rescue StandardError
      response.status = 422
    end

    def persist_request?
      false
    end

    private

    def save_resource
      resource = FHIR.from_contents(request.body.read)
      InfernoSuiteGenerator::KeptResourcesRepository.new.save(session_id: request.params[:session_id], resource:)
    end
  end

  # Fetches a resource previously saved via SaveResourceEndpoint.
  class FetchResourceEndpoint < Inferno::DSL::SuiteEndpoint
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

    def persist_request?
      false
    end

    private

    def kept_resource
      InfernoSuiteGenerator::KeptResourcesRepository.new.find(
        session_id: request.params[:session_id],
        resource_type: request.params[:resource_type],
        resource_id: request.params[:resource_id]
      )
    end
  end

  # Deletes all resources kept for a session (e.g. once a test run ends).
  class DeleteSessionResourcesEndpoint < Inferno::DSL::SuiteEndpoint
    def make_response
      InfernoSuiteGenerator::KeptResourcesRepository.new.delete_session(
        session_id: request.params[:session_id]
      )
      response.status = 204
    end

    def persist_request?
      false
    end
  end
end
