# frozen_string_literal: true

module InfernoSuiteGenerator
  module Plugins
    # Raised when a plugin cannot be found, loaded or run, or breaks the plugin contract.
    class Error < StandardError; end
  end
end
