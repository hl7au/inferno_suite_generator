# frozen_string_literal: true

require_relative "test_helper"
require "active_support/all"
require "sequel"
require "inferno_suite_generator/utils/kept_resources_repository"
require "fhir_models"

module InfernoSuiteGenerator
  # Covers `#save_all` (batched saves) and the cross-cutting resilience
  # behavior (`ensure_tables!` memoization, error swallowing) shared with
  # `#save`. Kept separate from KeptResourcesRepositoryTest, which was
  # already at this project's Metrics/ClassLength limit.
  class KeptResourcesRepositoryBatchTest < Minitest::Test
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

    private

    def with_repository_db(&)
      # `stub` calls its value if it responds to `:call` -- Sequel::Database
      # does (`db.call(sql)`), so the raw db object can't be passed directly;
      # wrap it in a lambda so `stub` treats it as a value generator instead.
      KeptResourcesRepository.stub(:db, -> { @db }, &)
    end
  end
end
