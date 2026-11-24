# frozen_string_literal: true

require_relative "questionnaire_usage_helpers"

module InfernoSuiteGenerator
  class QuestionnaireUsageFhirpathTest < Minitest::Test
    include QuestionnaireUsageHelpers

    PRONOUNS = "http://hl7.org/fhir/StructureDefinition/individual-pronouns"
    INDIGENOUS = "http://example.org/StructureDefinition/indigenous-status"
    SLICED = { id: "Patient.extension:indigenousStatus", url: INDIGENOUS }.freeze
    STATUS = "extension:indigenousStatus"
    SLICE_READS = %w[Slice Value Sub].zip([STATUS, "#{STATUS}.valueCoding", "#{STATUS}.extension[value].valueString"])
                                     .freeze

    # The item line of an item that pre-fills its answer.
    def prefill(label, *reads)
      "    - **#{label}**: pre-fills the answer#{"; reads #{reads.join(", ")}" unless reads.empty?}\n"
    end

    def unchecked(*paths) = paths.map { |path| "#{path} (not checked)" }

    def read_lines(items, root: [launch("patient", "Patient")], patient: group)
      item_lines(patient_entry(form(items, extension: root), patient:)["patient_read"])
    end

    def test_chained_variables_are_attributed_to_the_reading_item
      root = [launch("patient", "Patient"), variable("Name", "%patient.name.where(use = 'official').first()")]
      items = [item("family", "Family name", variable("Family", "%Name.family"), "%Family")]

      assert_equal [prefill("Family name", "name.family", *unchecked("name.use"))], read_lines(items, root:)
    end

    def test_item_variables_are_visible_below_only_and_root_variables_everywhere
      root = [launch("patient", "Patient"), variable("Born", "%patient.birthDate")]
      child = item("child", "Child", "%Local", "%Born")
      parent = item("parent", "Parent", variable("Local", "%patient.gender"), "%Local").merge("item" => [child])

      assert_equal [prefill("Parent", *unchecked("gender")), prefill("Child", *unchecked("gender", "birthDate")),
                    prefill("Sibling", *unchecked("birthDate"))],
                   read_lines([parent, item("sibling", "Sibling", "%Local", "%Born")], root:)
    end

    def test_variable_using_a_later_variable_is_logged_and_untraced
      root = [launch("patient", "Patient"), variable("Early", "%Late.gender"), variable("Late", "%patient")]
      names = item("names", "Names", variable("First", "%Second.family | %Third"), variable("Second", "%patient.name"),
                   variable("Third", "%patient.address"), "%First", "%Second.given", "%Early")

      assert_equal [prefill("Names", *unchecked("name.given")), prefill("Family name", "name.family"),
                    prefill("Marital status", *unchecked("maritalStatus"))], read_lines([names, *default_items], root:)
      assert_equal "Questionnaire usage tracing: untraced Demo form variable Early on root: it uses Late, " \
                   "defined after it\nQuestionnaire usage tracing: untraced Demo form variable First on names: " \
                   "it uses Second, Third, defined after it\n", @log
    end

    def test_where_arguments_read_paths_relative_to_the_filtered_element
      items = [item("this", "This", "%patient.name.where($this.use = 'official').family"),
               item("bare", "Bare", "%patient.telecom.where(system = 'phone' and resourceType = 'ContactPoint').value")]

      assert_equal [prefill("This", "name.family", *unchecked("name.use")),
                    prefill("Bare", *unchecked("telecom.value", "telecom.system"))], read_lines(items)
    end

    def test_exists_all_and_select_arguments_read_paths_relative_to_the_filtered_element
      items = [item("exists", "Exists", "%patient.contact.exists(name.where(use = 'usual').family = 'x')"),
               item("all", "All", "%patient.link.all(other.resourceType = 'Patient')"),
               item("select", "Select", "%patient.name.select(given.first()).count()")]

      assert_equal [prefill("Exists", *unchecked("contact", "contact.name.family", "contact.name.use")),
                    prefill("All", *unchecked("link", "link.other")),
                    prefill("Select", *unchecked("name", "name.given"))], read_lines(items)
    end

    def test_no_paths_are_read_after_stopping_functions
      items = [item("resolve", "Resolve", "%patient.generalPractitioner.resolve().name"),
               item("of_type", "OfType", "%patient.deceased.ofType(boolean).not()"),
               item("children", "Children", "%patient.contact.children().name"),
               item("descendants", "Descendants", "%patient.descendants().family"),
               item("select", "Select", "%patient.name.select(given).text")]

      assert_equal [prefill("Resolve", *unchecked("generalPractitioner")), prefill("OfType", *unchecked("deceased")),
                    prefill("Children", *unchecked("contact")), prefill("Descendants"),
                    prefill("Select", *unchecked("name", "name.given"))], read_lines(items)
    end

    def test_extension_reads_are_labelled_by_slice_or_url
      items = [item("pronouns", "Pronouns", "%patient.extension('#{PRONOUNS}').value"),
               item("modifier", "Modifier", "%patient.modifierExtension.where(url = 'http://e.org/x/flag').value"),
               item("other", "Other", "%patient.extension('#{INDIGENOUS}').extension('other').valueString")]

      assert_equal [prefill("Pronouns", *unchecked("extension[individual-pronouns].value")),
                    prefill("Modifier", *unchecked("modifierExtension[flag].value")),
                    prefill("Other", *unchecked("#{STATUS}.extension[other].valueString"))],
                   read_lines(items, patient: group(extensions: [SLICED]))
    end

    def test_must_support_extension_slice_is_checked_at_slice_value_and_value_sub_extension
      items = [item("slice", "Slice", "%patient.extension('#{INDIGENOUS}').exists()"),
               item("value", "Value", "%patient.extension.where(url = '#{INDIGENOUS}').valueCoding"),
               item("sub", "Sub", "%patient.extension('#{INDIGENOUS}').extension('value').valueString")]
      entry = patient_entry(form(items), patient: group(extensions: [SLICED]))

      assert_equal SLICE_READS.map { |label, path| prefill(label, path) }, item_lines(entry["patient_read"])
      assert_includes entry["patient_must_support"],
                      SLICE_READS.map { |label, path| "  - **#{path}**: #{label}\n" }.join
    end

    def test_module_form_reading_assembled_in_names_is_logged
      root = %w[encounter unused author].map { |name| { "url" => "#{SDC}assembleContext", "valueString" => name } }
      items = [item("a", "A", "%author.name", "%encounter.period.start", "%author.telecom")]

      assert_empty describe(ig(form(items, extension: root)), group)
      assert_equal "Questionnaire usage tracing: Demo form reads author, encounter from the form it is assembled " \
                   "into: trace the assembled form for their item uses\n", @log
    end
  end
end
