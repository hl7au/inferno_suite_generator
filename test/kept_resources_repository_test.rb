# frozen_string_literal: true

require_relative "test_helper"
require "active_support/all"
require "sequel"
require "inferno_suite_generator/utils/kept_resources_repository"
require "fhir_models"

module InfernoSuiteGenerator
  class KeptResourcesRepositoryTest < Minitest::Test
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

    def with_repository_db(&)
      # `stub` calls its value if it responds to `:call` -- Sequel::Database
      # does (`db.call(sql)`), so the raw db object can't be passed directly;
      # wrap it in a lambda so `stub` treats it as a value generator instead.
      KeptResourcesRepository.stub(:db, -> { @db }, &)
    end

    def age_ref!(session_id, seconds_ago)
      @db[KeptResourcesRepository::REFS_TABLE]
        .where(session_id:)
        .update(updated_at: Time.now - seconds_ago)
    end

    def with_expiration_ms(value)
      original = ENV.fetch("RESOURCE_KEEPER_EXPIRATION_MS", nil)
      ENV["RESOURCE_KEEPER_EXPIRATION_MS"] = value.to_s
      yield
    ensure
      ENV["RESOURCE_KEEPER_EXPIRATION_MS"] = original
    end
  end
end
