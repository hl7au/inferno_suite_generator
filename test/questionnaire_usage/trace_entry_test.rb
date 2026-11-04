# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Verifies what each kind of trace entry says about itself.
    class TraceEntryTest < Minitest::Test
      include TraceEntryFixtures

      INCLUDING = "Patient?family={{%name}}&_include=Patient:general-practitioner"

      def test_an_entry_is_shown_when_an_item_uses_it_beyond_a_variable
        assert_predicate launch_entry, :shown?
        refute_predicate launch_entry(used_in: []), :shown?
        refute_predicate launch_entry(used_in: [variable_usage]), :shown?
      end

      def test_a_query_with_its_own_include_is_shown_without_items
        assert_predicate query_entry(INCLUDING, used_in: []), :shown?
        refute_predicate query_entry("Patient?family={{%name}}", used_in: []), :shown?
      end

      def test_an_include_entry_is_shown_only_when_an_item_uses_it
        refute_predicate include_entry(LOCATION_QUERY, used_in: []), :shown?
      end

      def test_a_template_is_always_shown
        assert_predicate template_entry(patch: false, used_in: []), :shown?
      end

      def test_item_uses_leave_out_uses_that_only_define_a_variable
        dob = { link_id: "dob", text: "Date of birth", extension: "initialExpression" }

        assert_equal [dob], launch_entry(used_in: [variable_usage, dob]).item_uses
      end

      def test_a_search_query_gives_its_search_parameters_and_a_read_gives_none
        assert_equal %w[family gender], query_entry("Patient?family={{%name}}&gender=male").search_params
        assert_nil query_entry("Patient/{{%patient.id}}", read: true).search_params
        assert_nil launch_entry.search_params
      end

      def test_only_a_query_or_include_has_a_request
        assert_equal LOCATION_QUERY, include_entry(LOCATION_QUERY).query
        assert_nil launch_entry.query
      end

      def test_the_trace_file_fields_start_with_the_source
        assert_equal %i[source questionnaire_url questionnaire_version questionnaire_title name used_in],
                     launch_entry.to_h.keys
      end

      def test_each_kind_names_its_source_in_the_trace_file
        entries = [launch_entry, query_entry("Patient?family=x"), include_entry(LOCATION_QUERY),
                   template_entry(patch: false)]

        sources = entries.map { |entry| entry.to_h[:source] }

        assert_equal %w[launch_context query include template_extract], sources
      end

      def test_entries_of_one_version_of_a_form_share_a_form_key
        other_version = launch_entry(header: form_header.merge(questionnaire_version: "2"))

        assert_equal launch_entry.form_key, query_entry("Patient?family=x").form_key
        refute_equal launch_entry.form_key, other_version.form_key
      end

      def test_the_form_title_falls_back_to_the_url_then_the_id
        assert_equal FORM_TITLE, launch_entry.form_title
        assert_equal "url", TraceEntry::LaunchContext.new(questionnaire_url: "url").form_title
        assert_equal "id", TraceEntry::LaunchContext.new(questionnaire_id: "id").form_title
        assert_equal "Untitled questionnaire", TraceEntry::LaunchContext.new.form_title
      end

      def test_two_entries_with_the_same_fields_stay_apart
        assert_equal 2, [launch_entry, launch_entry].uniq.size
      end
    end
  end
end
