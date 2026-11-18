# frozen_string_literal: true

require_relative "test_helper"
require "active_support/all"
require "sequel"
require "rack/mock"
require "inferno_suite_generator/utils/session_resource_finder"
require "inferno_suite_generator/utils/session_resource_endpoint"

module InfernoSuiteGenerator
  # Points `SessionResourceFinder.db` at a throwaway in-memory SQLite database
  # holding a minimal copy of Inferno's `requests` table.
  module WithRequestLogDb
    def build_request_log_db
      Sequel.sqlite.tap do |db|
        db.create_table(:requests) do
          primary_key :index
          String :test_session_id, null: false
          String :url, text: true
          String :direction, null: false
          Integer :status
          String :response_body, text: true
        end
      end
    end

    def with_request_log_db(&)
      # `stub` calls its value if it responds to `:call` -- Sequel::Database
      # does (`db.call(sql)`), so the raw db object can't be passed directly;
      # wrap it in a lambda so `stub` treats it as a value generator instead.
      SessionResourceFinder.stub(:db, -> { @db }, &)
    end

    def log_response(body, session_id: "session-1", direction: "outgoing", status: 200)
      body = JSON.generate(body) unless body.is_a?(String)
      @db[:requests].insert(test_session_id: session_id, url: "http://fhir.example/", direction:, status:,
                            response_body: body)
    end

    def patient(id, gender)
      { "resourceType" => "Patient", "id" => id, "gender" => gender }
    end

    def bundle(*resources)
      { "resourceType" => "Bundle", "type" => "searchset", "entry" => resources.map { |r| { "resource" => r } } }
    end
  end

  class SessionResourceFinderTest < Minitest::Test
    include WithRequestLogDb

    def setup
      @db = build_request_log_db
      @finder = SessionResourceFinder.new
    end

    def test_a_read_response_is_returned_exactly_as_the_server_sent_it
      raw = %({ "resourceType": "Observation", "id": "obs-1", "valueQuantity": { "value": 1.10 } })

      with_request_log_db do
        log_response(raw)

        assert_equal raw, find("Observation", "obs-1")
      end
    end

    def test_a_search_result_is_extracted_from_its_bundle
      with_request_log_db do
        log_response(bundle(patient("patient-1", "male"), patient("patient-2", "female")))

        assert_equal patient("patient-2", "female"), JSON.parse(find("Patient", "patient-2"))
      end
    end

    def test_the_most_recent_copy_wins
      with_request_log_db do
        log_response(patient("patient-1", "male"))
        log_response(bundle(patient("patient-1", "female")))
        log_response(patient("patient-2", "other"))

        assert_equal "female", JSON.parse(find("Patient", "patient-1"))["gender"]
      end
    end

    def test_another_sessions_resource_is_not_found
      with_request_log_db do
        log_response(patient("patient-1", "male"), session_id: "session-2")

        assert_nil find("Patient", "patient-1")
      end
    end

    def test_a_resource_only_referenced_by_a_response_is_not_found
      observation = { "resourceType" => "Observation", "id" => "obs-1",
                      "subject" => { "type" => "Patient", "identifier" => { "value" => "patient-1" } } }

      with_request_log_db do
        log_response(observation)

        assert_nil find("Patient", "patient-1")
      end
    end

    def test_a_contained_resource_is_not_found
      observation = { "resourceType" => "Observation", "id" => "obs-1", "contained" => [patient("patient-1", "male")] }

      with_request_log_db do
        log_response(observation)

        assert_nil find("Patient", "patient-1")
      end
    end

    def test_non_json_and_non_object_bodies_are_skipped
      with_request_log_db do
        log_response(patient("patient-1", "male"))
        log_response(%(<Patient xmlns="http://hl7.org/fhir"><id value="patient-1"/> "Patient" "patient-1"</Patient>))
        log_response(%(["Patient", "patient-1"]))
        log_response(%({ "resourceType": "Bundle", "entry": ["Patient", "patient-1"] }))

        assert_equal patient("patient-1", "male"), JSON.parse(find("Patient", "patient-1"))
      end
    end

    def test_a_response_to_an_incoming_request_is_not_found
      with_request_log_db do
        log_response(patient("patient-1", "male"), direction: "incoming")

        assert_nil find("Patient", "patient-1")
      end
    end

    def test_a_failed_or_statusless_response_is_skipped
      with_request_log_db do
        log_response(patient("patient-1", "male"))
        log_response(patient("patient-1", "female"), status: 404)
        log_response(patient("patient-1", "other"), status: nil)

        assert_equal "male", JSON.parse(find("Patient", "patient-1"))["gender"]
      end
    end

    def test_only_the_newest_candidates_are_searched
      decoy = patient("patient-2", "patient-1")

      with_request_log_db do
        log_response(patient("patient-1", "male"))
        (SessionResourceFinder::MAX_CANDIDATES - 1).times { log_response(decoy) }

        refute_nil find("Patient", "patient-1")

        log_response(decoy)

        assert_nil find("Patient", "patient-1")
      end
    end

    def test_missing_resource_returns_nil
      with_request_log_db { assert_nil find("Patient", "nope") }
    end

    def test_blank_session_and_malformed_type_or_id_never_reach_the_database
      SessionResourceFinder.stub(:db, -> { raise "db must not be queried" }) do
        assert_nil @finder.find(session_id: "", resource_type: "Patient", resource_id: "patient-1")
        assert_nil find("Pat%ent", "patient-1")
        assert_nil find("Patient", "patient_%")
        assert_nil find("Patient", nil)
      end
    end

    private

    def find(resource_type, resource_id)
      @finder.find(session_id: "session-1", resource_type:, resource_id:)
    end
  end

  class FetchResourceEndpointTest < Minitest::Test
    include WithRequestLogDb

    FakeRequest = Struct.new(:params)
    FakeResponse = Struct.new(:status, :format, :body)

    PARAMS = { session_id: "session-1", resource_type: "Patient", resource_id: "patient-1" }.freeze

    def setup
      @db = build_request_log_db
      @endpoint = FetchResourceEndpoint.new
    end

    def test_returns_200_and_the_body_when_found
      raw = JSON.generate(patient("patient-1", "male"))
      res = FakeResponse.new

      with_request_log_db do
        log_response(raw)
        @endpoint.handle(FakeRequest.new(PARAMS), res)
      end

      assert_equal [200, :json, raw], [res.status, res.format, res.body]
    end

    def test_returns_404_when_not_found
      res = FakeResponse.new

      with_request_log_db { @endpoint.handle(FakeRequest.new(PARAMS), res) }

      assert_equal 404, res.status
    end

    def test_handle_halts_with_500_when_make_response_raises
      halted = @endpoint.session_resource_finder.stub(:find, ->(**) { raise "boom" }) do
        catch(:halt) { @endpoint.handle(FakeRequest.new(PARAMS), FakeResponse.new) }
      end

      assert_equal 500, halted.first
    end

    def test_skips_request_persistence
      refute @endpoint.persist_request?
    end
  end

  # Wraps the real Hanami endpoint, the way a generated suite registers it.
  class FhirpathLabCorsAroundFetchResourceEndpointTest < Minitest::Test
    include WithRequestLogDb

    LAB_ORIGIN = "https://fhirpath-lab.com"

    def setup
      @db = build_request_log_db
      @handler = FhirpathLabCors.new(FetchResourceEndpoint, lab_url: "#{LAB_ORIGIN}/FhirPath")
    end

    def test_a_session_resource_is_served_with_the_lab_origin_allowed
      raw = JSON.generate(patient("patient-1", "male"))

      status, headers, body = with_request_log_db do
        log_response(raw)
        get_resource("patient-1")
      end

      assert_equal [200, raw], [status, body.join]
      assert_equal LAB_ORIGIN, headers["Access-Control-Allow-Origin"]
    end

    def test_a_missing_resource_is_a_404_the_lab_origin_can_read
      status, headers, = with_request_log_db { get_resource("nope") }

      assert_equal 404, status
      assert_equal LAB_ORIGIN, headers["Access-Control-Allow-Origin"]
    end

    private

    def get_resource(resource_id)
      params = { session_id: "session-1", resource_type: "Patient", resource_id: }
      @handler.call(Rack::MockRequest.env_for("/", "HTTP_ORIGIN" => LAB_ORIGIN, "router.params" => params))
    end
  end
end
