# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator/utils/resource_keeper_client"
require "fhir_models"

module InfernoSuiteGenerator
  class ResourceKeeperClientTest < Minitest::Test
    FakeHttp = Struct.new(:response, :requests) do
      def request(req)
        requests << req
        response
      end
    end

    def setup
      @client = ResourceKeeperClient.new("http://keeper.example")
      @resource = FHIR::Patient.new(id: "patient-123")
    end

    def test_returns_true_on_successful_response
      with_fake_http(Net::HTTPCreated.new("1.1", "201", "Created")) do
        assert @client.save(session_id: "session-1", resource: @resource)
      end
    end

    def test_returns_false_on_error_response
      with_fake_http(Net::HTTPUnprocessableEntity.new("1.1", "422", "Unprocessable Entity")) do
        refute @client.save(session_id: "session-1", resource: @resource)
      end
    end

    def test_returns_false_and_does_not_raise_on_network_error
      Net::HTTP.stub(:start, ->(*) { raise Errno::ECONNREFUSED }) do
        refute @client.save(session_id: "session-1", resource: @resource)
      end
    end

    def test_returns_false_when_base_url_is_blank
      client = ResourceKeeperClient.new("")

      refute client.save(session_id: "session-1", resource: @resource)
    end

    def test_returns_false_when_session_id_is_blank
      refute @client.save(session_id: "", resource: @resource)
    end

    def test_returns_false_when_resource_is_nil
      refute @client.save(session_id: "session-1", resource: nil)
    end

    def test_posts_expected_payload
      fake_http = FakeHttp.new(Net::HTTPCreated.new("1.1", "201", "Created"), [])

      Net::HTTP.stub(:start, ->(*_args, &blk) { blk.call(fake_http) }) do
        @client.save(session_id: "session-1", resource: @resource)
      end

      sent_request = fake_http.requests.first
      payload = JSON.parse(sent_request.body)
      assert_equal "session-1", payload["sessionId"]
      assert_equal "Patient", payload["resourceType"]
      assert_equal "patient-123", payload["resourceId"]
      assert_equal "patient-123", payload["resource"]["id"]
    end

    private

    def with_fake_http(response)
      fake_http = FakeHttp.new(response, [])
      Net::HTTP.stub(:start, ->(*_args, &blk) { blk.call(fake_http) }) do
        yield
      end
    end
  end
end
