# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator/questionnaire_usage_tracing/ast"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # Verifies `Ast` reads `%Name` references and element paths from the
    # FHIRPath AST, using expressions from the 715 Health Check and GP CCMP forms.
    class AstTest < Minitest::Test
      RECORDED_SEX_URL = "http://hl7.org/fhir/StructureDefinition/individual-recordedSexOrGender"

      def test_references_returns_the_external_constant_names
        assert_equal ["ObsBodyHeight"], Ast.references("%ObsBodyHeight.entry")
      end

      def test_references_lists_each_name_once
        assert_equal %w[A B], Ast.references("%A.x | %B.where(y = %A.z)")
      end

      def test_references_strips_backticks
        assert_equal ["vs-x"], Ast.references("%`vs-x`.code")
      end

      def test_references_ignores_a_name_inside_a_string_literal
        assert_empty Ast.references("'%Foo'")
      end

      def test_references_returns_empty_and_logs_on_bad_syntax
        assert_output(/skipping FHIRPath/) { assert_empty Ast.references("%%bad((") }
      end

      def test_paths_returns_empty_and_logs_on_bad_syntax
        assert_output(/skipping FHIRPath/) { assert_empty Ast.paths("%%bad((", "bad", bundle: false) }
      end

      def test_paths_ignores_chains_from_other_names
        assert_empty Ast.paths("%patient.birthDate", "user", bundle: false)
      end

      def test_paths_drops_function_calls
        assert_paths [{ type: nil, path: "birthDate", stopped: false }],
                     "%patient.birthDate.toString()", "patient"
      end

      def test_paths_drops_a_where_filter_on_a_member
        assert_paths [{ type: nil, path: "telecom.value", stopped: false }],
                     "%patient.telecom.where(system='phone').value", "patient"
      end

      def test_paths_keeps_the_url_of_an_extension_filter
        assert_paths [{ type: nil, path: "extension[url=#{RECORDED_SEX_URL}]", stopped: false }],
                     "%patient.extension.where(url='#{RECORDED_SEX_URL}').exists()", "patient"
      end

      def test_paths_keeps_the_url_of_the_extension_function
        assert_paths [{ type: nil, path: "extension[url=#{RECORDED_SEX_URL}]", stopped: false }],
                     "%patient.extension('#{RECORDED_SEX_URL}').exists()", "patient"
      end

      def test_paths_gives_an_empty_path_for_a_chain_that_only_picks_the_resource
        assert_paths [{ type: nil, path: "", stopped: false }],
                     "%ObsBodyHeight.entry.resource.where(status = 'final' or status = 'amended').first()",
                     "ObsBodyHeight", bundle: true
      end

      def test_paths_stops_at_select
        assert_paths [{ type: nil, path: "name", stopped: true }],
                     "%user.name.select(given.first() + ' ' + family)", "user"
      end

      def test_paths_stops_at_of_type_outside_a_bundle
        assert_paths [{ type: nil, path: "value", stopped: true }],
                     "%obs.value.ofType(Quantity).value", "obs"
      end

      def test_paths_reads_the_type_of_a_bundle_chain_from_of_type
        assert_paths [{ type: "Location", path: "", stopped: false }],
                     "%PractitionerRoleLocation.entry.resource.ofType(Location)",
                     "PractitionerRoleLocation", bundle: true
      end

      def test_paths_reads_the_query_own_type_from_of_type
        assert_paths [{ type: "MedicationStatement", path: "", stopped: false }],
                     "%MedicationStatement.entry.resource.ofType(MedicationStatement)",
                     "MedicationStatement", bundle: true
      end

      def test_paths_finds_chains_nested_in_function_arguments
        expression = "%MedicationStatement.entry.resource.ofType(Medication)" \
                     ".where(id in %MedicationStatement.entry.resource.medication.select(reference))"

        assert_paths [{ type: "Medication", path: "", stopped: false },
                      { type: nil, path: "medication", stopped: true }],
                     expression, "MedicationStatement", bundle: true
      end

      def test_paths_reads_an_alias_chain
        assert_paths [{ type: nil, path: "value.value", stopped: false }],
                     "%ObsBodyHeightLatest.value.where(unit = 'cm').value", "ObsBodyHeightLatest"
      end

      private

      def assert_paths(expected, expression, name, bundle: false)
        assert_equal expected, Ast.paths(expression, name, bundle:)
      end
    end
  end
end
