# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Verifies which tests list each trace entry, without rendering anything.
    class DeliveryTest < Minitest::Test
      include TraceEntryFixtures

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
        assert_empty tested_by(launch_entry(used_in: [variable_use]))
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
        assert_equal [entry], listing.placements.map(&:entry)
        assert_equal [@patient], listing.groups
      end

      def test_a_shared_include_is_listed_once_with_every_group_it_was_traced_for
        role, first, second = shared_include_groups
        entry = include_entry(ROLE_QUERY)
        delivery = Delivery.new([role, first, second], { "first" => [entry], "second" => [entry] })

        listing = delivery.test_listings.sole

        assert_equal "role_include", listing.destination.test_id
        assert_equal [entry], listing.placements.map(&:entry)
        assert_equal [first, second], listing.groups
      end

      def test_two_equal_entries_of_a_group_stay_apart
        entries = [launch_entry, launch_entry]
        listing = Delivery.new([@patient], { @patient.profile_url => entries }).test_listings.sole

        assert_equal 2, listing.placements.size
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

    # Verifies what Delivery decides for an entry traced for several groups.
    class DeliverySharedEntryTest < Minitest::Test
      include TraceEntryFixtures

      def test_a_shared_entry_has_one_answer_for_every_group
        shared_placements.each do |placement|
          assert placement.reads.fetch("birthDate").checked
          refute placement.reads.fetch("contact").checked
        end
      end

      def test_only_the_group_that_checks_an_element_lists_it_in_its_must_support_test
        unchecking, checking = shared_placements

        assert_empty unchecking.must_support_reads
        assert_nil unchecking.must_support
        assert_equal ["birthDate"], checking.must_support_reads.keys
        assert_equal "checking_must_support", checking.must_support.test_id
      end

      def test_a_shared_read_is_named_as_the_group_that_checks_it_names_it
        path = "extension[url=#{INDIGENOUS_STATUS}].value"
        entry = launch_entry(reads: [path])
        traces = { "unchecking" => [entry], AU_CORE_PATIENT => [entry] }

        _group, placements = Delivery.new([unchecking_group, patient_group], traces).to_enum(:each_group).first

        assert_equal "extension:indigenousStatus.value", placements.sole.reads.fetch(path).label
      end

      def test_a_group_names_its_must_support_reads_itself
        entry = launch_entry(reads: ["extension[url=#{INDIGENOUS_STATUS}].value"])
        traces = { "unchecking" => [entry], AU_CORE_PATIENT => [entry] }

        _group, placements = Delivery.new([unchecking_group, patient_group], traces).to_enum(:each_group).to_a.last

        assert_equal ["extension:indigenousStatus.value"], placements.sole.must_support_reads.values.map(&:label)
      end

      private

      # The placements of one entry traced for a group that doesn't check
      # birthDate and one that does, in that order.
      def shared_placements
        checking = patient_group
        add_test(checking, "checking_must_support", "must_support")
        unchecking = unchecking_group
        add_test(unchecking, "unchecking_must_support", "must_support")
        entry = launch_entry(reads: %w[birthDate contact])
        delivery = Delivery.new([unchecking, checking], { "unchecking" => [entry], AU_CORE_PATIENT => [entry] })
        delivery.to_enum(:each_group).map { |_group, placements| placements.sole }
      end

      def unchecking_group
        InfernoSuiteGenerator::Generator::GroupMetadata.new(resource: "Patient", profile_url: "unchecking")
      end

      def add_test(group, id, kind, **details)
        group.add_test(id:, file_name: "#{id}.rb", kind:, **details)
      end
    end
  end
end
