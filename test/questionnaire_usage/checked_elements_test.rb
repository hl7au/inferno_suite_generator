# frozen_string_literal: true

require_relative "support"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Groups and assertions shared by the `CheckedElements` tests.
    module CheckedElementsFixtures
      include UsageSectionFixtures

      def indigenous
        "extension[url=#{INDIGENOUS_STATUS}]"
      end

      def group(elements: [], mandatory: [], extensions: [])
        InfernoSuiteGenerator::Generator::GroupMetadata.new(
          resource: "Patient", mandatory_elements: mandatory,
          must_supports: { elements: elements.map { |path| { path: } }, extensions: }
        )
      end

      def label(group, path)
        CheckedElements.new([group]).label(path)
      end

      def assert_checked(group, path)
        assert CheckedElements.new([group]).checked?(path), "Expected #{path} to count as checked"
      end

      def refute_checked(group, path)
        refute CheckedElements.new([group]).checked?(path), "Expected #{path} not to count as checked"
      end
    end

    # Verifies which element paths a group's tests check.
    class CheckedElementsTest < Minitest::Test
      include CheckedElementsFixtures

      def test_must_support_elements_count_as_checked
        assert_checked patient_group, "birthDate"
        refute_checked patient_group, "contact"
      end

      def test_a_child_of_a_checked_element_needs_its_own_path
        assert_checked group(elements: ["contact.name"]), "contact.name"
        refute_checked group(elements: ["contact"]), "contact.name"
      end

      def test_mandatory_elements_count_as_checked_without_their_type
        assert_checked patient_group, "gender"
        assert_checked group(mandatory: ["Patient.contact.name"]), "contact.name"
      end

      def test_id_always_counts_as_checked
        assert_checked group, "id"
        refute_checked group, "contact.id"
      end

      def test_a_group_without_must_supports_checks_only_id
        none = InfernoSuiteGenerator::Generator::GroupMetadata.new(resource: "Patient")

        assert_checked none, "id"
        refute_checked none, "birthDate"
      end

      # The profile marks `deceasedBoolean` with a type slice on `deceased[x]`;
      # FHIRPath reads it as `deceased`.
      def test_a_choice_element_with_a_type_slice_counts_as_checked
        assert_checked patient_group, "deceased"
      end

      def test_a_choice_element_read_by_its_type_counts_as_checked
        assert_checked patient_group, "deceasedBoolean"
        refute_checked patient_group, "deceasedDateTime.value"
      end

      def test_a_path_inside_a_choice_element_is_compared_by_the_element
        typed = group(elements: ["value[x]:valueQuantity.value"])

        assert_checked typed, "valueQuantity.value"
        refute_checked typed, "valueQuantity.unit"
      end

      def test_a_nested_choice_element_counts_under_its_parent_only
        nested = group(elements: ["component.value[x]"])

        assert_checked nested, "component.valueQuantity"
        refute_checked nested, "valueQuantity"
      end

      def test_a_name_that_only_starts_like_a_choice_element_does_not_count
        refute_checked group(elements: ["value[x]"]), "values"
      end
    end

    # Verifies how extensions count and are labeled, and how several groups
    # combine.
    class CheckedElementsExtensionTest < Minitest::Test
      include CheckedElementsFixtures

      def test_a_must_support_extension_and_what_it_holds_count_as_checked
        assert_checked patient_group, indigenous
        assert_checked patient_group, "#{indigenous}.value"
      end

      def test_an_extension_the_profile_does_not_slice_does_not_count
        refute_checked patient_group, "extension[url=#{PRONOUNS}].value"
      end

      def test_a_must_support_extension_is_labeled_by_its_slice
        assert_equal "extension:indigenousStatus.value", label(patient_group, "#{indigenous}.value")
      end

      def test_any_other_extension_is_labeled_by_the_end_of_its_url
        assert_equal "extension[individual-pronouns].extension[value].value",
                     label(patient_group, "extension[url=#{PRONOUNS}].extension[url=value].value")
      end

      def test_an_extension_slice_counts_under_its_parent_only
        sliced = group(extensions: [{ id: "Patient.address.extension:state", url: INDIGENOUS_STATUS }])

        assert_equal "address.extension:state", label(sliced, "address.#{indigenous}")
        assert_equal "extension[indigenous-status]", label(sliced, indigenous)
        refute_checked sliced, indigenous
      end

      def test_a_modifier_extension_is_labeled_by_its_slice
        sliced = group(extensions: [{ id: "Patient.modifierExtension:status", url: INDIGENOUS_STATUS }])

        assert_equal "modifierExtension:status", label(sliced, "modifierExtension[url=#{INDIGENOUS_STATUS}]")
      end

      def test_other_paths_keep_their_label
        assert_equal "contact.name.family", label(patient_group, "contact.name.family")
      end

      def test_a_path_counts_as_checked_when_any_group_checks_it
        elements = CheckedElements.new([group, patient_group])

        assert elements.checked?("birthDate")
        refute elements.checked?("contact")
      end

      def test_a_path_is_labeled_as_the_group_that_checks_it_names_it
        elements = CheckedElements.new([group, patient_group])

        assert_equal "extension:indigenousStatus", elements.label(indigenous)
      end

      def test_a_path_no_group_checks_is_labeled_as_the_first_group_names_it
        first = group(extensions: [{ id: "Patient.address.extension:state", url: PRONOUNS }])
        elements = CheckedElements.new([first, patient_group])

        assert_equal "extension[individual-pronouns]", elements.label("extension[url=#{PRONOUNS}]")
      end
    end
  end
end
