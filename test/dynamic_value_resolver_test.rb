# frozen_string_literal: true

require_relative "test_helper"
require "date"
require "inferno_suite_generator/core/config/dynamic_value_resolver"
require "inferno_suite_generator/core/config/utils"

module InfernoSuiteGenerator
  class Generator
    class GeneratorConfigKeeper
      class DynamicValueResolverTest < Minitest::Test
        class Host
          include DynamicValueResolver
        end

        def setup
          @resolver = Host.new
        end

        def test_time_now_standalone_resolves_to_iso_date
          result = @resolver.resolve_dynamic_values("${Time.now}")
          assert_equal Date.today.iso8601, result
        end

        def test_time_now_with_fhir_ge_prefix
          result = @resolver.resolve_dynamic_values("ge${Time.now}")
          assert_equal "ge#{Date.today.iso8601}", result
        end

        def test_time_now_with_fhir_le_prefix
          result = @resolver.resolve_dynamic_values("le${Time.now}")
          assert_equal "le#{Date.today.iso8601}", result
        end

        def test_datetime_now_standalone_resolves_to_iso_datetime
          result = @resolver.resolve_dynamic_values("${DateTime.now}")
          assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\z/, result)
        end

        def test_datetime_now_with_fhir_ge_prefix
          result = @resolver.resolve_dynamic_values("ge${DateTime.now}")
          assert result.start_with?("ge")
          assert_match(/\Age\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\z/, result)
        end

        def test_array_with_mixed_static_and_dynamic_elements
          input  = ["ge${Time.now}", "le2050-01-01"]
          result = @resolver.resolve_dynamic_values(input)
          assert_equal ["ge#{Date.today.iso8601}", "le2050-01-01"], result
        end

        def test_array_all_dynamic_elements
          result = @resolver.resolve_dynamic_values(["${Time.now}", "${Time.now}"])
          assert_equal [Date.today.iso8601, Date.today.iso8601], result
        end

        def test_static_string_passes_through_unchanged
          assert_equal "ge1950-01-01", @resolver.resolve_dynamic_values("ge1950-01-01")
        end

        def test_nil_passes_through_unchanged
          assert_nil @resolver.resolve_dynamic_values(nil)
        end

        def test_integer_passes_through_unchanged
          assert_equal 42, @resolver.resolve_dynamic_values(42)
        end

        def test_unknown_token_is_left_as_is
          assert_equal "${Foo.bar}", @resolver.resolve_dynamic_values("${Foo.bar}")
        end

        def test_empty_string_passes_through_unchanged
          assert_equal "", @resolver.resolve_dynamic_values("")
        end

        def test_empty_array_passes_through_unchanged
          assert_equal [], @resolver.resolve_dynamic_values([])
        end
      end

      class ResolveFromConstantsTest < Minitest::Test
        class UtilsHost
          include Utils

          def initialize(config)
            @config = config
          end
        end

        def test_resolves_time_now_token_in_constant_string
          host = UtilsHost.new("constants" => { "search_default_values.date" => "ge${Time.now}" })
          assert_equal "ge#{Date.today.iso8601}", host.resolve_from_constants("search_default_values.date")
        end

        def test_resolves_datetime_now_token_in_constant_string
          host = UtilsHost.new("constants" => { "search_default_values.dt" => "${DateTime.now}" })
          result = host.resolve_from_constants("search_default_values.dt")
          assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\z/, result)
        end

        def test_resolves_time_now_token_in_constant_array
          host = UtilsHost.new("constants" => { "search_default_values.date" => ["ge${Time.now}", "le2050-01-01"] })
          assert_equal ["ge#{Date.today.iso8601}", "le2050-01-01"],
                       host.resolve_from_constants("search_default_values.date")
        end

        def test_passes_through_static_constant_unchanged
          host = UtilsHost.new("constants" => { "search_default_values.code" => "active" })
          assert_equal "active", host.resolve_from_constants("search_default_values.code")
        end

        def test_resolves_token_in_literal_value_when_no_constant_match
          host = UtilsHost.new("constants" => {})
          assert_equal "ge#{Date.today.iso8601}", host.resolve_from_constants("ge${Time.now}")
        end
      end
    end
  end
end
