# frozen_string_literal: true

require_relative "test_helper"
require "active_support/all"
require "sequel"
require "stringio"
require "fhir_models"
require "inferno_suite_generator/utils/kept_resources_repository"
require "inferno_suite_generator/utils/resource_keeper_endpoints"

module InfernoSuiteGenerator
  # Points `KeptResourcesRepository.db` at a throwaway in-memory SQLite database
  # for the duration of the block. Shared by every resource-keeper test class.
  module WithRepositoryDb
    def with_repository_db(&)
      # `stub` calls its value if it responds to `:call` -- Sequel::Database
      # does (`db.call(sql)`), so the raw db object can't be passed directly;
      # wrap it in a lambda so `stub` treats it as a value generator instead.
      KeptResourcesRepository.stub(:db, -> { @db }, &)
    end
  end

  class KeptResourcesRepositoryTest < Minitest::Test
    include WithRepositoryDb

    def setup
      @db = Sequel.sqlite
      @repository = KeptResourcesRepository.new
    end

    def test_save_then_find_round_trip
      resource = FHIR::Patient.new(id: "patient-1", gender: "male")

      with_repository_db do
        assert @repository.save(session_id: "session-1", resource:)

        found = @repository.find(session_id: "session-1", resource_type: "Patient", resource_id: "patient-1")
        assert_equal resource.to_json, found[:resource_json]
      end
    end

    def test_find_returns_nil_when_missing
      with_repository_db do
        assert_nil @repository.find(session_id: "session-1", resource_type: "Patient", resource_id: "nope")
      end
    end

    def test_save_updates_existing_row_instead_of_creating_a_new_one
      resource_v1 = FHIR::Patient.new(id: "patient-1", gender: "male")
      resource_v2 = FHIR::Patient.new(id: "patient-1", gender: "female")

      with_repository_db do
        @repository.save(session_id: "session-1", resource: resource_v1)
        @repository.save(session_id: "session-1", resource: resource_v2)

        assert_equal 1, @db[KeptResourcesRepository::REFS_TABLE].count
        found = @repository.find(session_id: "session-1", resource_type: "Patient", resource_id: "patient-1")
        assert_equal resource_v2.to_json, found[:resource_json]
      end
    end

    def test_save_deduplicates_identical_bodies_across_sessions
      resource = FHIR::Patient.new(id: "patient-1", gender: "male")

      with_repository_db do
        @repository.save(session_id: "session-1", resource:)
        @repository.save(session_id: "session-2", resource:)

        assert_equal 2, @db[KeptResourcesRepository::REFS_TABLE].count
        assert_equal 1, @db[KeptResourcesRepository::BODIES_TABLE].count
      end
    end

    def test_save_returns_false_when_session_id_or_resource_is_blank
      with_repository_db do
        refute @repository.save(session_id: "", resource: FHIR::Patient.new(id: "patient-1"))
        refute @repository.save(session_id: "session-1", resource: nil)
      end
    end

    def test_delete_session_removes_only_that_sessions_refs
      resource = FHIR::Patient.new(id: "patient-1", gender: "male")

      with_repository_db do
        @repository.save(session_id: "session-1", resource:)
        @repository.save(session_id: "session-2", resource:)

        @repository.delete_session(session_id: "session-1")

        assert_nil @repository.find(session_id: "session-1", resource_type: "Patient", resource_id: "patient-1")
        refute_nil @repository.find(session_id: "session-2", resource_type: "Patient", resource_id: "patient-1")
      end
    end

    def test_delete_session_leaves_the_body_row_in_place
      resource = FHIR::Patient.new(id: "patient-1", gender: "male")

      with_repository_db do
        @repository.save(session_id: "session-1", resource:)
        @repository.delete_session(session_id: "session-1")

        assert_equal 1, @db[KeptResourcesRepository::BODIES_TABLE].count
      end
    end

    def test_find_returns_nil_for_an_expired_ref_without_deleting_the_row
      resource = FHIR::Patient.new(id: "patient-1", gender: "male")

      with_repository_db do
        @repository.save(session_id: "session-1", resource:)
        age_ref!("session-1", 8 * 24 * 60 * 60)

        with_expiration_ms(KeptResourcesRepository::DEFAULT_EXPIRATION_MS) do
          assert_nil @repository.find(session_id: "session-1", resource_type: "Patient", resource_id: "patient-1")
        end

        assert_equal 1, @db[KeptResourcesRepository::REFS_TABLE].count
      end
    end

    def test_find_respects_a_custom_expiration_env_var
      resource = FHIR::Patient.new(id: "patient-1", gender: "male")

      with_repository_db do
        @repository.save(session_id: "session-1", resource:)
        age_ref!("session-1", 60)

        with_expiration_ms(1000) do
          assert_nil @repository.find(session_id: "session-1", resource_type: "Patient", resource_id: "patient-1")
        end
      end
    end

    private

    def age_ref!(session_id, seconds_ago)
      @db[KeptResourcesRepository::REFS_TABLE]
        .where(session_id:)
        .update(updated_at: Time.now - seconds_ago)
    end

    def with_expiration_ms(value)
      # `ENV.fetch(key, nil)` trips fasterer's fetch-with-argument check, and
      # `ENV.fetch(key) { nil }` trips rubocop's redundant-block check -- a
      # plain lookup is exactly what we want anyway, so sidestep both.
      original = ENV["RESOURCE_KEEPER_EXPIRATION_MS"] # rubocop:disable Style/FetchEnvVar
      ENV["RESOURCE_KEEPER_EXPIRATION_MS"] = value.to_s
      yield
    ensure
      ENV["RESOURCE_KEEPER_EXPIRATION_MS"] = original
    end
  end

  # Covers `#save_all` (batched saves) and the cross-cutting resilience
  # behavior (`ensure_tables!` memoization, error swallowing) shared with
  # `#save`. Kept separate from KeptResourcesRepositoryTest, which is at
  # this project's Metrics/ClassLength limit.
  class KeptResourcesRepositoryBatchTest < Minitest::Test
    include WithRepositoryDb

    def setup
      @db = Sequel.sqlite
      @repository = KeptResourcesRepository.new
    end

    def test_save_returns_false_on_a_db_error_instead_of_raising
      # A resource without an id violates the refs table's NOT NULL constraint.
      resource_without_id = FHIR::Patient.new(gender: "male")

      with_repository_db do
        refute @repository.save(session_id: "session-1", resource: resource_without_id)
      end
    end

    def test_save_all_saves_every_resource_in_one_transaction
      resources = [
        FHIR::Patient.new(id: "patient-1", gender: "male"),
        FHIR::Patient.new(id: "patient-2", gender: "female")
      ]

      with_repository_db do
        assert @repository.save_all(session_id: "session-1", resources:)

        assert_equal 2, @db[KeptResourcesRepository::REFS_TABLE].count
        found = @repository.find(session_id: "session-1", resource_type: "Patient", resource_id: "patient-2")
        assert_equal resources.last.to_json, found[:resource_json]
      end
    end

    def test_save_all_deduplicates_repeated_refs_within_the_same_batch
      resources = [
        FHIR::Patient.new(id: "patient-1", gender: "male"),
        FHIR::Patient.new(id: "patient-1", gender: "female")
      ]

      with_repository_db do
        assert @repository.save_all(session_id: "session-1", resources:)

        assert_equal 1, @db[KeptResourcesRepository::REFS_TABLE].count
        found = @repository.find(session_id: "session-1", resource_type: "Patient", resource_id: "patient-1")
        assert_equal resources.last.to_json, found[:resource_json]
      end
    end

    def test_save_all_returns_true_for_an_empty_list
      with_repository_db { assert @repository.save_all(session_id: "session-1", resources: []) }
    end

    def test_save_all_returns_false_when_session_id_is_blank
      with_repository_db do
        refute @repository.save_all(session_id: "", resources: [FHIR::Patient.new(id: "patient-1")])
      end
    end

    def test_ensure_tables_reruns_after_the_db_connection_changes
      with_repository_db { @repository.save(session_id: "session-1", resource: FHIR::Patient.new(id: "patient-1")) }

      new_db = Sequel.sqlite
      KeptResourcesRepository.stub(:db, -> { new_db }) do
        assert @repository.save(session_id: "session-1", resource: FHIR::Patient.new(id: "patient-1"))
        assert_equal 1, new_db[KeptResourcesRepository::REFS_TABLE].count
      end
    end
  end

  class ResourceKeeperEndpointsTest < Minitest::Test
    include WithRepositoryDb

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
  end
end
