# frozen_string_literal: true

# Kept so suites generated before the resource keeper was removed still boot
# without regeneration. Remove in the next minor release.
require_relative "session_resource_endpoint"
require_relative "kept_resources_repository"

module InfernoSuiteGenerator
  # Old suites still register `DELETE /custom/<suite_id>/resources/:session_id`.
  # Served resources now disappear with the session, so there is nothing to delete.
  class DeleteSessionResourcesEndpoint < Inferno::DSL::SuiteEndpoint
    include StatelessSuiteEndpoint

    def make_response
      response.status = 204
    end
  end
end
