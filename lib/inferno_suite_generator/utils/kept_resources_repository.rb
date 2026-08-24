# frozen_string_literal: true

require "digest"

module InfernoSuiteGenerator
  # Stores FHIR resources fetched during a test run so they can be fetched
  # back later (e.g. by FHIRPath Lab, to evaluate a failing expression against
  # the actual resource content).
  #
  # Storage is split into a content-addressable blob store
  # (+kept_resource_bodies+) and a thin per-resource ref table
  # (+kept_fhir_resources+). Most Inferno test kits run repeatedly against a
  # stable reference/synthetic FHIR server, so the same resource is often
  # fetched with an identical body across many sessions; splitting the body
  # out lets those sessions share one copy instead of storing it once per
  # session.
  class KeptResourcesRepository
    BODIES_TABLE = :kept_resource_bodies
    REFS_TABLE = :kept_fhir_resources
    DEFAULT_EXPIRATION_MS = 7 * 24 * 60 * 60 * 1000 # 7 days

    def self.db
      Inferno::Application["db.connection"]
    end

    def self.expiration_ms
      ENV.fetch("RESOURCE_KEEPER_EXPIRATION_MS") { DEFAULT_EXPIRATION_MS }.to_i
    end

    def self.ensure_tables!
      return if @tables_ensured_for.equal?(db)

      ensure_bodies_table!
      ensure_refs_table!
      @tables_ensured_for = db
    end

    def self.ensure_bodies_table!
      db.create_table?(BODIES_TABLE) do
        String :content_hash, primary_key: true, size: 64 # SHA-256 hex digest
        String :resource_json, text: true, null: false
        DateTime :created_at, null: false
      end
    end

    def self.ensure_refs_table!
      db.create_table?(REFS_TABLE) do
        String :session_id, null: false, size: 36
        String :resource_type, null: false, size: 255
        String :resource_id, null: false, size: 255
        String :content_hash, null: false, size: 64
        DateTime :updated_at, null: false
        primary_key %i[session_id resource_type resource_id]
        index :content_hash
      end
    end

    # A single save is just a batch of one: same transaction, same multi-row
    # (here, single-row) `ON CONFLICT` statements as `save_all`.
    def save(session_id:, resource:)
      return false if session_id.blank? || resource.nil?

      self.class.ensure_tables!
      self.class.db.transaction { save_batch(session_id, rows_for([resource])) }
      true
    rescue StandardError => e
      log_save_failure(:save, e)
      false
    end

    # Saves several resources in one transaction/round trip instead of one
    # `save` call per resource (e.g. for a whole search bundle's results).
    def save_all(session_id:, resources:)
      resources = Array(resources).compact
      return true if resources.empty?
      return false if session_id.blank?

      self.class.ensure_tables!
      self.class.db.transaction { save_batch(session_id, rows_for(resources)) }
      true
    rescue StandardError => e
      log_save_failure(:save_all, e)
      false
    end

    # Returns nil for a missing OR expired ref — callers can't tell the
    # difference, and shouldn't need to: both mean "treat this as 404".
    def find(session_id:, resource_type:, resource_id:)
      self.class.ensure_tables!
      ref = self.class.db[self.class::REFS_TABLE].first(session_id:, resource_type:, resource_id:)
      return nil if ref.nil? || expired?(ref[:updated_at])

      self.class.db[self.class::BODIES_TABLE].first(content_hash: ref[:content_hash])
    end

    # Deletes ref rows only — bodies are left in place even if this was the
    # last ref pointing at one. Not worth garbage collecting: since expiry
    # never deletes ref rows either, an orphaned blob costs nothing worse
    # than the already-accepted unbounded growth of the ref table.
    def delete_session(session_id:)
      self.class.ensure_tables!
      self.class.db[self.class::REFS_TABLE].where(session_id:).delete
    end

    private

    def log_save_failure(method_name, error)
      Inferno::Application["logger"].error("KeptResourcesRepository##{method_name} failed: #{error.full_message}")
    end

    def save_batch(session_id, rows)
      now = Time.now
      save_bodies(rows, now)
      save_refs(session_id, rows, now)
    end

    def ref_conflict_update
      { content_hash: Sequel[:excluded][:content_hash], updated_at: Sequel[:excluded][:updated_at] }
    end

    def rows_for(resources)
      rows = resources.map do |resource|
        body = resource.to_json
        { resource_type: resource.resourceType, resource_id: resource.id,
          content_hash: Digest::SHA256.hexdigest(body), resource_json: body }
      end
      # A multi-row `ON CONFLICT ... DO UPDATE` can't affect the same row
      # twice in one statement (Postgres raises on this) -- collapse
      # duplicate refs within this batch, keeping the most current copy.
      rows.reverse.uniq { |row| [row[:resource_type], row[:resource_id]] }.reverse
    end

    def save_bodies(rows, now)
      self.class.db[self.class::BODIES_TABLE]
          .insert_conflict(target: :content_hash)
          .import(%i[content_hash resource_json created_at],
                  rows.map { |row| [row[:content_hash], row[:resource_json], now] })
    end

    def save_refs(session_id, rows, now)
      self.class.db[self.class::REFS_TABLE]
          .insert_conflict(target: %i[session_id resource_type resource_id], update: ref_conflict_update)
          .import(%i[session_id resource_type resource_id content_hash updated_at],
                  rows.map { |row| [session_id, row[:resource_type], row[:resource_id], row[:content_hash], now] })
    end

    def expired?(updated_at)
      updated_at < Time.now - (self.class.expiration_ms / 1000.0)
    end
  end
end
