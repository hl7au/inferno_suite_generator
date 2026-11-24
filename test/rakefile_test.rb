# frozen_string_literal: true

require_relative "test_helper"
require "rake"

module InfernoSuiteGenerator
  class RakefileTest < Minitest::Test
    def test_default_task_runs_tests_rubocop_and_reek
      app = Rake.with_application { load File.expand_path("../Rakefile", __dir__) }

      assert_equal %w[test rubocop reek], app["default"].prerequisites
      assert app.lookup("reek"), "the Rakefile defines a reek task"
    end
  end
end
