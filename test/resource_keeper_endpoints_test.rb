# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator/utils/resource_keeper_endpoints"

module InfernoSuiteGenerator
  # Suites generated before the resource keeper was removed require this file
  # and register both endpoints.
  class ResourceKeeperEndpointsTest < Minitest::Test
    FakeRequest = Struct.new(:params)
    FakeResponse = Struct.new(:status)

    def test_old_require_path_still_provides_the_fetch_endpoint
      assert_operator FetchResourceEndpoint, :<, Inferno::DSL::SuiteEndpoint
    end

    def test_delete_endpoint_answers_204_without_touching_anything
      res = FakeResponse.new

      DeleteSessionResourcesEndpoint.new.handle(FakeRequest.new({ session_id: "session-1" }), res)

      assert_equal 204, res.status
    end

    def test_delete_endpoint_skips_request_persistence
      refute DeleteSessionResourcesEndpoint.new.persist_request?
    end
  end
end
