# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Verifies which test `Router` picks for each kind of source.
    class RouterTest < Minitest::Test
      include TracerFixtures

      LOCATION_QUERY = "PractitionerRole?practitioner={{%user.id}}&_include=PractitionerRole:location"

      def setup
        @patient = group("Patient", read: {}, must_support: {}, create: {}, update: { option: "update" },
                                    search: [{ search_names: %w[family gender] }])
        @role = group("PractitionerRole", include: [{ search_names: ["_id"], include_targets: ["Location"] },
                                                    { search_names: ["practitioner"],
                                                      include_targets: ["Location"] }])
        @location = group("Location")
        @router = Router.new([@patient, @role, @location])
      end

      def test_a_launch_context_and_a_read_go_to_the_read_test
        assert_equal "patient_read", test_id(@patient, TraceEntry::LaunchContext.new)
        read = TraceEntry::Query.new(query: "Patient/{{%patient.id}}", read: true)

        assert_equal "patient_read", test_id(@patient, read)
      end

      def test_a_search_goes_to_the_search_test_by_the_same_parameters_in_any_order
        destination = route(@patient, TraceEntry::Query.new(query: "Patient?gender=male&family={{%name}}&_count=1"))

        assert_equal "patient_search_1", destination.test_id
        assert_equal "search by family + gender", destination.label
      end

      def test_a_search_no_test_makes_goes_nowhere
        assert_nil route(@patient, TraceEntry::Query.new(query: "Patient?name=x"))
        assert_nil route(@patient, TraceEntry::Query.new(query: "Patient?_sort=-birthdate"))
      end

      def test_an_include_goes_to_the_include_test_of_the_searching_group
        destination = route(@location, TraceEntry::Include.new(query: LOCATION_QUERY))

        assert_equal @role, destination.group
        assert_equal "practitionerrole_include_2", destination.test_id
        assert_equal "include", destination.kind
      end

      def test_an_include_falls_back_to_any_include_test_for_its_type
        query = "PractitionerRole?organization=x&_include=PractitionerRole:location"

        assert_equal "practitionerrole_include_1", test_id(@location, TraceEntry::Include.new(query:))
      end

      def test_templates_go_to_the_create_test_or_for_a_patch_to_the_patch_then_update_test
        assert_equal "patient_create", test_id(@patient, TraceEntry::Template.new(patch: false))
        assert_equal "patient_update", test_id(@patient, TraceEntry::Template.new(patch: true))
        assert_nil route(@location, TraceEntry::Template.new(patch: false))
      end

      def test_a_patch_ignores_an_update_test_that_creates_a_new_resource
        encounter = group("Encounter", update: [{ option: "update_new" }, { option: "update" }])

        assert_equal "encounter_update_2", test_id(encounter, TraceEntry::Template.new(patch: true))
      end

      def test_the_must_support_test
        assert_equal "patient_must_support", @router.must_support_test(@patient).test_id
        assert_nil @router.must_support_test(@location)
      end

      private

      def route(group, entry)
        @router.source_test(group, entry)
      end

      def test_id(group, entry)
        route(group, entry)&.test_id
      end

      # A group with tests of these kinds, each kind with one details hash or a list of them.
      def group(resource, **tests)
        InfernoSuiteGenerator::Generator::GroupMetadata.new(resource:, title: resource, searches: []).tap do |group|
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
