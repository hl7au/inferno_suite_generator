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

    # Verifies which test makes the request of each kind of source.
    class DeliveryRequestTest < Minitest::Test
      include TraceEntryFixtures

      LOCATION_QUERY = "PractitionerRole?practitioner={{%user.id}}&_include=PractitionerRole:location"

      def setup
        @patient = group("Patient", read: {}, create: {}, update: { option: "update" },
                                    search: [{ search_names: %w[family gender] }])
        @role = group("PractitionerRole", include: [{ search_names: ["_id"], include_targets: ["Location"] },
                                                    { search_names: ["practitioner"],
                                                      include_targets: ["Location"] }])
        @location = group("Location")
        @groups = [@patient, @role, @location]
      end

      def test_a_launch_context_and_a_read_go_to_the_read_test
        assert_equal "patient_read", test_id(@patient, launch_entry)
        assert_equal "patient_read", test_id(@patient, query_entry("Patient/{{%patient.id}}"))
      end

      def test_a_search_goes_to_the_search_test_by_the_same_parameters_in_any_order
        destination = route(@patient, query_entry("Patient?gender=male&family={{%name}}&_count=1"))

        assert_equal "patient_search_1", destination.test_id
        assert_equal "search by family + gender", destination.label
      end

      def test_a_search_no_test_makes_goes_nowhere
        assert_nil route(@patient, query_entry("Patient?name=x"))
        assert_nil route(@patient, query_entry("Patient?_sort=-birthdate"))
      end

      def test_an_include_goes_to_the_include_test_of_the_searching_group
        destination = route(@location, include_entry(LOCATION_QUERY))

        assert_equal @role, destination.group
        assert_equal "practitionerrole_include_2", destination.test_id
        assert_equal "include", destination.kind
        assert_equal "search with _include in PractitionerRole", destination.label
      end

      def test_an_include_falls_back_to_any_include_test_for_its_type
        query = "PractitionerRole?organization=x&_include=PractitionerRole:location"

        assert_equal "practitionerrole_include_1", test_id(@location, include_entry(query))
      end

      def test_templates_go_to_the_create_test_or_for_a_patch_to_the_patch_then_update_test
        assert_equal "patient_create", test_id(@patient, template_entry(patch: false))
        assert_equal "patient_update", test_id(@patient, template_entry(patch: true))
        assert_nil route(@location, template_entry(patch: false))
      end

      def test_a_patch_ignores_an_update_test_that_creates_a_new_resource
        encounter = group("Encounter", update: [{ option: "update_new" }, { option: "update" }])
        @groups << encounter

        assert_equal "encounter_update_2", test_id(encounter, template_entry(patch: true))
      end

      private

      def route(group, entry)
        delivery = Delivery.new(@groups, { group.profile_url => [entry] })
        delivery.to_enum(:each_group).to_h.fetch(group).sole.request
      end

      def test_id(group, entry)
        route(group, entry)&.test_id
      end

      # A group with tests of these kinds, each kind with one details hash or a list of them.
      def group(resource, **tests)
        InfernoSuiteGenerator::Generator::GroupMetadata.new(resource:, profile_url: resource, title: resource,
                                                            searches: []).tap do |group|
          tests.each do |kind, details|
            Array.wrap(details).each.with_index(1) do |test_details, index|
              id = [resource.downcase, kind, (index if details.is_a?(Array))].compact.join("_")
              group.add_test(id:, file_name: "#{id}.rb", kind: kind.to_s, **test_details)
            end
          end
        end
      end
    end
  end
end
