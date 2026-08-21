# frozen_string_literal: true

require_relative "test_helper"
require "active_support/all"
require "sequel"
require "stringio"
require "fhir_models"
require "inferno_suite_generator/utils/resource_keeper_endpoints"

module InfernoSuiteGenerator
  class ResourceKeeperEndpointsTest < Minitest::Test
    FakeRequest = Struct.new(:params, :body)
    FakeResponse = Struct.new(:status, :format, :body)

    def setup
      @db = Sequel.sqlite
    end

    def test_fetch_resource_endpoint_returns_200_and_the_body_when_found
      resource = FHIR::Patient.new(id: "patient-1", gender: "male")
      endpoint = FetchResourceEndpoint.new

      with_repository_db do
        endpoint.kept_resources_repository.save(session_id: "session-1", resource:)

        req = build_request(params: { session_id: "session-1", resource_type: "Patient", resource_id: "patient-1" })
        res = FakeResponse.new
        endpoint.handle(req, res)

        assert_equal [200, :json, resource.to_json], [res.status, res.format, res.body]
      end
    end

    def test_fetch_resource_endpoint_returns_404_when_not_found
      endpoint = FetchResourceEndpoint.new
      req = build_request(params: { session_id: "session-1", resource_type: "Patient", resource_id: "nope" })
      res = FakeResponse.new

      with_repository_db { endpoint.handle(req, res) }

      assert_equal 404, res.status
    end

    def test_delete_session_resources_endpoint_returns_204_and_deletes_the_refs
      resource = FHIR::Patient.new(id: "patient-1", gender: "male")
      endpoint = DeleteSessionResourcesEndpoint.new

      with_repository_db do
        endpoint.kept_resources_repository.save(session_id: "session-1", resource:)

        req = build_request(params: { session_id: "session-1" })
        res = FakeResponse.new
        endpoint.handle(req, res)

        assert_equal 204, res.status
        assert_nil kept_resource(endpoint, resource_type: "Patient", resource_id: "patient-1")
      end
    end

    def test_handle_halts_with_500_when_make_response_raises
      endpoint = FetchResourceEndpoint.new
      req = build_request(params: { session_id: "session-1", resource_type: "Patient", resource_id: "patient-1" })
      res = FakeResponse.new

      halted = with_repository_db do
        endpoint.kept_resources_repository.stub(:find, ->(**) { raise "boom" }) do
          catch(:halt) { endpoint.handle(req, res) }
        end
      end

      assert_equal 500, halted.first
    end

    def test_all_resource_keeper_endpoints_skip_request_persistence
      [FetchResourceEndpoint, DeleteSessionResourcesEndpoint].each do |klass|
        refute klass.new.persist_request?, "#{klass} should not persist requests"
      end
    end

    def test_kept_resources_repository_is_memoized_per_endpoint_instance
      endpoint = FetchResourceEndpoint.new
      assert_same endpoint.kept_resources_repository, endpoint.kept_resources_repository
    end

    private

    def build_request(params:, body: nil)
      FakeRequest.new(params, StringIO.new(body.to_s))
    end

    def kept_resource(endpoint, resource_type:, resource_id:)
      endpoint.kept_resources_repository.find(session_id: "session-1", resource_type:, resource_id:)
    end

    def with_repository_db(&)
      # `stub` calls its value if it responds to `:call` -- Sequel::Database
      # does (`db.call(sql)`), so the raw db object can't be passed directly;
      # wrap it in a lambda so `stub` treats it as a value generator instead.
      KeptResourcesRepository.stub(:db, -> { @db }, &)
    end
  end
end
