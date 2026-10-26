# frozen_string_literal: true

require_relative "support"

module InfernoSuitePlugins
  module QuestionnaireUsageTracing
    # Verifies which test `Router` picks for each kind of source.
    class RouterTest < Minitest::Test
      include TracerFixtures

      # The two Context methods Router uses.
      FakeContext = Struct.new(:groups) do
        def test_index(group)
          InfernoSuiteGenerator::Plugins::TestIndex.new(group)
        end
      end

      LOCATION_QUERY = "PractitionerRole?practitioner={{%user.id}}&_include=PractitionerRole:location"

      def setup
        @patient = group("Patient", read: {}, must_support: {}, create: {}, update: { option: "new" },
                                    search: [{ search_names: %w[family gender] }])
        @role = group("PractitionerRole", include: [{ search_names: ["_id"], include_targets: ["Location"] },
                                                    { search_names: ["practitioner"],
                                                      include_targets: ["Location"] }])
        @location = group("Location")
        @router = Router.new(FakeContext.new([@patient, @role, @location]))
      end

      def test_a_launch_context_and_a_read_go_to_the_read_test
        assert_equal "patient_read", test_id(@patient, source: "launch_context")
        assert_equal "patient_read", test_id(@patient, source: "query", query: "Patient/{{%patient.id}}", read: true)
      end

      def test_a_search_goes_to_the_search_test_by_the_same_parameters_in_any_order
        destination = route(@patient, source: "query", query: "Patient?gender=male&family={{%name}}&_count=1")

        assert_equal "patient_search_1", destination.test_id
        assert_equal "search by family + gender", destination.label
      end

      def test_a_search_no_test_makes_goes_nowhere
        assert_nil route(@patient, source: "query", query: "Patient?name=x")
        assert_nil route(@patient, source: "query", query: "Patient?_sort=-birthdate")
      end

      def test_an_include_goes_to_the_include_test_of_the_searching_group
        destination = route(@location, source: "include", query: LOCATION_QUERY, include: "PractitionerRole:location")

        assert_equal @role, destination.group
        assert_equal "practitionerrole_include_2", destination.test_id
        assert_equal "include", destination.kind
      end

      def test_an_include_falls_back_to_any_include_test_for_its_type
        query = "PractitionerRole?organization=x&_include=PractitionerRole:location"

        assert_equal "practitionerrole_include_1", test_id(@location, source: "include", query:)
      end

      def test_templates_go_to_the_create_test_or_for_a_patch_to_the_patch_then_update_test
        assert_equal "patient_create", test_id(@patient, source: "template_extract", patch: false)
        assert_equal "patient_update", test_id(@patient, source: "template_extract", patch: true)
        assert_nil route(@location, source: "template_extract", patch: false)
      end

      def test_the_must_support_test
        assert_equal "patient_must_support", @router.must_support_test(@patient).test_id
        assert_nil @router.must_support_test(@location)
      end

      private

      def route(group, **entry)
        @router.source_test(group, entry)
      end

      def test_id(group, **entry)
        route(group, **entry)&.test_id
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
