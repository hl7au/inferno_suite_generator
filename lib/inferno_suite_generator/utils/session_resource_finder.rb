# frozen_string_literal: true

require "json"

module InfernoSuiteGenerator
  # Finds a FHIR resource a test session received from the server under test,
  # by reading the response bodies Inferno already logs for that session.
  # Nothing is stored here, so retention follows the host's session purge.
  class SessionResourceFinder
    REQUESTS_TABLE = :requests
    RESOURCE_TYPE_PATTERN = /\A[A-Z][A-Za-z]{0,63}\z/
    RESOURCE_ID_PATTERN = /\A[A-Za-z0-9\-.]{1,64}\z/
    SUCCESS_STATUSES = (200..299)
    # A resource only found in an older response than the newest
    # MAX_CANDIDATES candidates is reported as missing.
    MAX_CANDIDATES = 20

    def self.db
      Inferno::Application["db.connection"]
    end

    # Returns the resource as a JSON string, or nil. When the session received
    # the resource more than once, the most recent copy wins.
    def find(session_id:, resource_type:, resource_id:)
      return nil if session_id.blank?
      return nil unless RESOURCE_TYPE_PATTERN.match?(resource_type.to_s) && RESOURCE_ID_PATTERN.match?(resource_id.to_s)

      candidate_indexes(session_id, resource_type, resource_id).each do |index|
        json = extract(response_body(index), resource_type, resource_id)
        return json if json
      end
      nil
    end

    private

    def requests
      self.class.db[REQUESTS_TABLE]
    end

    # The LIKE filters only narrow the scan; `extract` decides. Both values are
    # pattern-checked above, so neither can carry a LIKE wildcard. Incoming rows
    # hold responses Inferno wrote itself, not the server under test.
    def candidate_indexes(session_id, resource_type, resource_id)
      requests
        .where(test_session_id: session_id, direction: "outgoing", status: SUCCESS_STATUSES)
        .where(Sequel.like(:response_body, "%\"#{resource_id}\"%"))
        .where(Sequel.like(:response_body, "%\"#{resource_type}\"%"))
        .reverse_order(:index)
        .limit(MAX_CANDIDATES)
        .select_map(:index)
    end

    # Bodies are loaded one at a time: a search bundle can be large, the first
    # candidate is usually the match, and Sequel on Postgres buffers a whole
    # result set unless it uses a cursor.
    def response_body(index)
      requests.where(index:).get(:response_body)
    end

    def extract(body, resource_type, resource_id)
      parsed = JSON.parse(body)
      # A read response is returned untouched, exactly as the server sent it.
      return body if target?(parsed, resource_type, resource_id)

      entry_resource = bundle_resources(parsed).find { |resource| target?(resource, resource_type, resource_id) }
      entry_resource && JSON.generate(entry_resource)
    rescue JSON::ParserError, TypeError
      nil
    end

    def target?(resource, resource_type, resource_id)
      resource.is_a?(Hash) && resource["resourceType"] == resource_type && resource["id"] == resource_id
    end

    def bundle_resources(parsed)
      return [] unless parsed.is_a?(Hash) && parsed["resourceType"] == "Bundle" && parsed["entry"].is_a?(Array)

      parsed["entry"].filter_map { |entry| entry["resource"] if entry.is_a?(Hash) }
    end
  end
end
