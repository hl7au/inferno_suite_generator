# frozen_string_literal: true

module InfernoSuiteGenerator
  # The BasicTestHelpers module provides shared helper methods for InfernoSuiteGenerator tests,
  # including default payloads and configurations used across multiple test cases.
  module BasicTestHelpers
    def deep_copy_hash(hash_data)
      Marshal.load(Marshal.dump(hash_data))
    rescue StandardError => e
      raise "Failed to deep copy hash: #{e.message}"
    end

    def default_patch_body_list
      {
        FHIRPATHPatchJson: {
          resource_type => []
        },
        JSONPatch: {
          resource_type => []
        }
      }
    end
  end
end
