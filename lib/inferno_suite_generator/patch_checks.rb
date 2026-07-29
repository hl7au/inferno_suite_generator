# frozen_string_literal: true

module InfernoSuiteGenerator
  # Single source of truth for the checks `PatchTest#assert_patch_success` can perform,
  # and the default for the `configs.generic.patch_checks` config option.
  PATCH_CHECKS = %w[status version diff].freeze
end
