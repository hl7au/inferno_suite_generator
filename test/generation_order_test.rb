# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  # Pins the order in which test files are generated, because that order becomes the order the
  # tests run in inside a group: GroupMetadata#add_test appends as each generator runs, and
  # GroupGenerator emits "test from:" straight from that list.
  #
  # Chained search tests have to be generated after the _include tests. A chained parameter draws
  # its candidate identifiers from the scratch of the type it chains to, and for a target outside
  # the patient compartment (practitioner:Practitioner.identifier on PractitionerRole) the only
  # thing that populates that scratch is the _include test for the same reference.
  class GenerationOrderTest < Minitest::Test
    # Records which generation steps run, in order, without touching the IG package or disk.
    class OrderRecordingGenerator < Generator
      attr_reader :steps

      def initialize
        super("unused")
        @steps = []
      end

      %i[
        load_ig_package extract_metadata extract_demodata
        generate_search_tests generate_read_tests generate_provenance_revinclude_search_tests
        generate_include_search_tests generate_chain_search_tests generate_validation_tests
        generate_must_support_tests generate_reference_resolution_tests generate_create_tests
        generate_update_tests generate_patch_tests generate_groups generate_suites use_tests
      ].each do |step|
        define_method(step) do
          @steps << step
          nil
        end
      end
    end

    def setup
      @generator = OrderRecordingGenerator.new
      @generator.generate
    end

    # Fails rather than blowing up on a nil comparison when a step is not reached at all, which is
    # what happens when chain generation is nested inside another step instead of being its own.
    def index_of(step)
      index = @generator.steps.index(step)
      refute_nil index, "#{step} was never reached during generate"
      index
    end

    def test_chain_search_tests_are_generated_after_include_search_tests
      assert index_of(:generate_chain_search_tests) > index_of(:generate_include_search_tests),
             "chained search tests must be generated after the _include tests that populate the " \
             "scratch they read their candidate identifiers from"
    end

    # Chain tests still belong with the searches rather than trailing the whole group.
    def test_chain_search_tests_are_generated_before_the_closing_tests
      %i[generate_validation_tests generate_must_support_tests generate_reference_resolution_tests]
        .each do |later_step|
        assert index_of(:generate_chain_search_tests) < index_of(later_step),
               "chained search tests should still precede #{later_step}"
      end
    end

    def test_groups_are_generated_after_every_test_type
      last_test_step = index_of(:generate_patch_tests)

      assert index_of(:generate_groups) > last_test_step,
             "groups collect the tests, so they must be generated last"
    end
  end
end
