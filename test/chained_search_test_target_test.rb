# frozen_string_literal: true

require_relative "test_helper"
require "active_support/all"
require "inferno_suite_generator/test_modules/chained_search_test"

module InfernoSuiteGenerator
  # Covers how a chained search decides which resources to draw its candidate identifiers from,
  # and what it reports when there are none.
  #
  # A chained parameter names the type it chains to ("practitioner:Practitioner.identifier"), and
  # the candidates have to come from that type's scratch. Drawing them from Patient scratch
  # regardless meant any chain onto a non-Patient target found nothing, issued no request, and
  # still failed with a message about the response.
  class ChainedSearchTestTargetTest < Minitest::Test
    # Minimal include host. Only the collaborators the methods under test touch are provided;
    # `omit` is captured rather than raised so the message can be asserted on.
    class ChainHost
      include ChainedSearchTest

      attr_accessor :scratch
      attr_reader :omitted_with, :searches

      def initialize(scratch)
        @scratch = scratch
        @searches = []
        @omitted_with = nil
      end

      def omit(message)
        @omitted_with = message
        throw :omitted
      end

      def search_and_check_response(params)
        @searches << params
      end

      def fetch_all_bundled_resources = []
    end

    # Stand-ins for the FHIR models: the code under test only reads resourceType and the
    # identifier's system and value.
    Identifier = Struct.new(:system, :value)
    Resource = Struct.new(:resourceType, :identifier)

    IDENTIFIER = Identifier.new("http://ns.electronichealth.net.au/id/hi/hpii/1.0", "8003611566719005").freeze

    def practitioner = Resource.new("Practitioner", [IDENTIFIER])

    def patient = Resource.new("Patient", [IDENTIFIER])

    def test_chain_target_drives_the_scratch_key
      host = ChainHost.new({})

      assert_equal %i[patient_resources], host.chain_target_scratch_keys("Patient")
      assert_equal %i[practitioner_resources], host.chain_target_scratch_keys("Practitioner")
    end

    # Included resources are keyed by downcase and a test's own scratch by snake_case, so both
    # spellings are accepted for a multi-word target rather than one being guessed.
    def test_multi_word_target_accepts_both_scratch_conventions
      host = ChainHost.new({})

      assert_equal %i[practitioner_role_resources practitionerrole_resources],
                   host.chain_target_scratch_keys("PractitionerRole")
    end

    def test_resources_are_read_from_the_target_scratch_not_patient_scratch
      host = ChainHost.new(
        patient_resources: { "pat-1" => [patient] },
        practitioner_resources: { "pat-1" => [practitioner] }
      )

      found = host.chain_target_resources("Practitioner")

      assert_equal ["pat-1"], found.keys
      assert_equal "Practitioner", found["pat-1"].first.resourceType
    end

    def test_chain_onto_a_non_patient_target_finds_its_candidates
      host = ChainHost.new(practitioner_resources: { "pat-1" => [practitioner] })

      candidates = host.all_chain_identifier_values(
        ["pat-1"], host.chain_target_resources("Practitioner"), "Practitioner", nil
      )

      refute_empty candidates, "a Practitioner chain should find the Practitioner in its own scratch"
      assert_equal "8003611566719005", candidates.first[:identifier].value
    end

    # The regression: Practitioner candidates are not in Patient scratch, so the old lookup
    # produced an empty list for every server and every run.
    def test_patient_scratch_holds_no_candidates_for_a_practitioner_chain
      host = ChainHost.new(patient_resources: { "pat-1" => [patient] })

      candidates = host.all_chain_identifier_values(
        ["pat-1"], host.scratch[:patient_resources], "Practitioner", nil
      )

      assert_empty candidates
    end

    def test_no_candidates_omits_without_issuing_a_request
      host = ChainHost.new({})

      catch(:omitted) do
        host.run_chain_search_test_clean(
          "practitioner:Practitioner.identifier", ["pat-1"], nil, ["practitioner"], nil
        )
        flunk "expected the test to omit when no candidate identifier could be built"
      end

      assert_empty host.searches, "no request should be made when there is nothing to search on"
      assert_match(/No Practitioner resource/, host.omitted_with)
      assert_match(/Nothing was requested from the server/, host.omitted_with)
    end
  end
end
