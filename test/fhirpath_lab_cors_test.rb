# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator/utils/fhirpath_lab_cors"

module InfernoSuiteGenerator
  class FhirpathLabCorsTest < Minitest::Test
    LAB_URL = "https://fhirpath-lab.com/FhirPath"
    LAB_ORIGIN = "https://fhirpath-lab.com"
    OK_APP = ->(_env) { [200, { "Content-Type" => "application/json" }, ["{}"]] }

    def test_origin_of_drops_the_path
      assert_equal LAB_ORIGIN, FhirpathLabCors.origin_of(LAB_URL)
    end

    def test_origin_of_keeps_a_non_default_port
      assert_equal "http://localhost:3000", FhirpathLabCors.origin_of("http://localhost:3000/FhirPath")
    end

    def test_origin_of_matches_the_lowercase_origin_a_browser_sends
      assert_equal LAB_ORIGIN, FhirpathLabCors.origin_of(" https://FHIRPath-Lab.com/FhirPath ")
    end

    def test_origin_of_is_nil_for_a_url_without_an_http_origin
      [nil, "", "not a url", "/FhirPath"].each do |url|
        assert_nil FhirpathLabCors.origin_of(url), "expected no origin for #{url.inspect}"
      end
    end

    def test_get_from_the_lab_origin_is_readable_cross_origin
      status, headers, body = get(origin: LAB_ORIGIN)

      assert_equal [200, ["{}"]], [status, body]
      assert_equal LAB_ORIGIN, headers["Access-Control-Allow-Origin"]
      assert_equal "Origin", headers["Vary"]
      assert_equal "application/json", headers["Content-Type"]
    end

    def test_get_from_another_origin_gets_no_allow_origin
      _status, headers, _body = get(origin: "https://evil.example")

      refute headers.key?("Access-Control-Allow-Origin")
      assert_equal "Origin", headers["Vary"]
    end

    def test_get_without_an_origin_gets_no_allow_origin
      _status, headers, _body = get(origin: nil)

      refute headers.key?("Access-Control-Allow-Origin")
    end

    def test_a_not_found_response_is_still_readable_by_the_lab_origin
      status, headers, _body = get(origin: LAB_ORIGIN, app: ->(_env) { [404, {}, []] })

      assert_equal 404, status
      assert_equal LAB_ORIGIN, headers["Access-Control-Allow-Origin"]
    end

    def test_no_origin_is_allowed_when_the_lab_url_is_blank
      _status, headers, _body = get(origin: "null", lab_url: "")

      refute headers.key?("Access-Control-Allow-Origin")
    end

    def test_preflight_from_the_lab_origin_allows_get_with_the_headers_the_lab_sends
      status, headers, body = request("OPTIONS", origin: LAB_ORIGIN)

      assert_equal [204, []], [status, body]
      assert_equal LAB_ORIGIN, headers["Access-Control-Allow-Origin"]
      assert_equal "GET", headers["Access-Control-Allow-Methods"]
      assert_equal "Accept, Cache-Control", headers["Access-Control-Allow-Headers"]
      assert_equal "Origin", headers["Vary"]
    end

    def test_preflight_from_another_origin_allows_nothing
      status, headers, _body = request("OPTIONS", origin: "https://evil.example")

      assert_equal 204, status
      assert_equal({ "Vary" => "Origin" }, headers)
    end

    def test_preflight_never_reaches_the_wrapped_endpoint
      status, = request("OPTIONS", origin: LAB_ORIGIN, app: ->(_env) { raise "endpoint was called" })

      assert_equal 204, status
    end

    private

    def get(origin:, app: OK_APP, lab_url: LAB_URL)
      request("GET", origin:, app:, lab_url:)
    end

    def request(method, origin:, app: OK_APP, lab_url: LAB_URL)
      env = { "REQUEST_METHOD" => method }
      env["HTTP_ORIGIN"] = origin if origin
      FhirpathLabCors.new(app, lab_url:).call(env)
    end
  end
end
