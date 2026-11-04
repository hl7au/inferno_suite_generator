# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Verifies which tests list each trace entry, without rendering anything.
    class DeliveryTest < Minitest::Test
      include UsageSectionFixtures

      ROLE_QUERY = "PractitionerRole?practitioner={{%user.id}}&_include=PractitionerRole:location"

      def setup
        @patient = patient_group
        add_test(@patient, "patient_read", "read")
        add_test(@patient, "patient_must_support", "must_support")
      end

      def test_an_entry_goes_to_the_test_of_its_request_and_the_must_support_test_it_reads_for
        assert_equal %w[patient_read patient_must_support], tested_by(launch_entry)
      end

      def test_an_entry_that_reads_no_checked_element_skips_the_must_support_test
        assert_equal %w[patient_read], tested_by(launch_entry(reads: ["contact"]))
      end

      def test_a_group_without_a_must_support_test_lists_the_request_only
        group = patient_group
        add_test(group, "patient_read", "read")

        assert_equal %w[patient_read], tested_by(launch_entry, group:)
      end

      def test_an_entry_that_is_not_shown_is_listed_by_no_test
        assert_empty tested_by(launch_entry(used_in: [variable_usage]))
      end

      def test_an_entry_with_no_test_for_its_request_is_listed_by_no_test
        assert_empty tested_by(launch_entry(reads: ["contact"]), group: patient_group)
      end

      def test_a_group_no_entry_links_to_is_left_out
        delivery = Delivery.new([@patient], {})

        assert_empty delivery.to_enum(:each_group).to_a
        assert_empty delivery.test_listings
      end

      def test_a_listing_has_the_entries_of_the_test_and_their_group
        entry = launch_entry
        listing = Delivery.new([@patient], { @patient.profile_url => [entry] }).test_listings.first

        assert_equal "patient_read", listing.destination.test_id
        assert_equal [entry], listing.entries
        assert_equal [@patient], listing.groups
      end

      def test_a_shared_include_is_listed_once_with_every_group_it_was_traced_for
        role, first, second = shared_include_groups
        entry = { source: "include", **form_header, name: "Q", query: ROLE_QUERY, include: "PractitionerRole:location",
                  used_in: [{ link_id: "name", text: "Name", extension: "initialExpression" }] }
        delivery = Delivery.new([role, first, second], { "first" => [entry], "second" => [entry] })

        listing = delivery.test_listings.sole

        assert_equal "role_include", listing.destination.test_id
        assert_equal 1, listing.entries.size
        assert_equal [first, second], listing.groups
      end

      def test_two_equal_entries_of_a_group_stay_apart
        entries = [launch_entry, launch_entry]

        assert_equal 2, Delivery.new([@patient], { @patient.profile_url => entries }).test_listings.sole.entries.size
      end

      private

      def tested_by(entry, group: @patient)
        _group, placements = Delivery.new([group], { group.profile_url => [entry] }).to_enum(:each_group).first
        placements.sole.tests.map(&:test_id)
      end

      def add_test(group, id, kind, **details)
        group.add_test(id:, file_name: "#{id}.rb", kind:, **details)
      end

      def shared_include_groups
        role = location_group("PractitionerRole", "role")
        add_test(role, "role_include", "include", search_names: ["practitioner"], include_targets: ["Location"])
        [role, location_group("Location", "first"), location_group("Location", "second")]
      end

      def location_group(resource, profile_url)
        InfernoSuiteGenerator::Generator::GroupMetadata.new(resource:, profile_url:, title: profile_url, searches: [])
      end
    end
  end
end
