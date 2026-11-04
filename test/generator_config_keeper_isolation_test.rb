# frozen_string_literal: true

require_relative "test_helper"
require_relative "generator_fixtures"

module InfernoSuiteGenerator
  # Each keeper merges its config files into its own hash, so one keeper's config can't reach the next.
  class GeneratorConfigKeeperIsolationTest < Minitest::Test
    include GeneratorFixtures

    def test_a_keeper_does_not_see_the_config_of_an_earlier_one
      build_config_keeper({ "configs" => { "generic" => { "search_params_to_ignore" => ["_sort"] } } })

      assert_empty build_config_keeper.search_params_to_ignore
    end
  end
end
