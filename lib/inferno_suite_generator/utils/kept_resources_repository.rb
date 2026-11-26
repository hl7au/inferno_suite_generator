# frozen_string_literal: true

module InfernoSuiteGenerator
  # Kept so test kits that still call the resource keeper directly (for example
  # au-ps-inferno's hand-written suite) keep running against this revision.
  # Nothing is stored: FetchResourceEndpoint now reads the session's request
  # log. Remove in the next minor release.
  class KeptResourcesRepository
    # Accepts the old `session_id:` and `resource:` keywords and ignores them.
    def save(**_keywords)
      true
    end

    # Accepts the old `session_id:` and `resources:` keywords and ignores them.
    def save_all(**_keywords)
      true
    end
  end
end
