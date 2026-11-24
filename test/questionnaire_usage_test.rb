# frozen_string_literal: true

require_relative "test_helper"
require_relative "generator_fixtures"
require "tmpdir"
require "minitest/mock"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  # Builds small questionnaires and groups, and reads what `QuestionnaireUsage.descriptions` writes for them.
  module QuestionnaireUsageFixtures
    include GeneratorFixtures

    SDC = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-"
    PATCH_URL = "https://smartforms.csiro.au/ig/StructureDefinition/TemplateExtractExtensionPatchRequestUrl"
    PROFILE = "http://example.org/StructureDefinition/"
    ROLE_QUERY = "PractitionerRole?practitioner={{%user.id}}&_include=PractitionerRole:location"

    def questionnaire(extension: [], item: [], contained: [], **fields)
      { "resourceType" => "Questionnaire", "url" => "http://example.org/Questionnaire/form", "version" => "1.0",
        "title" => "Form", "status" => "draft", "contained" => contained, "extension" => extension,
        "item" => item }.merge(fields.transform_keys(&:to_s)).compact
    end

    def item(link_id, text, *extensions, children: [])
      { "linkId" => link_id, "text" => text, "type" => children.empty? ? "string" : "group",
        "extension" => extensions, "item" => children }
    end

    # An item that pre-fills its answer from `fhirpath`.
    def reading(link_id, text, fhirpath)
      item(link_id, text, expression("initialExpression", fhirpath))
    end

    def expression(name, fhirpath)
      { "url" => "#{SDC}#{name}", "valueExpression" => { "language" => "text/fhirpath", "expression" => fhirpath } }
    end

    def variable(name, expression, language = "text/fhirpath")
      { "url" => "http://hl7.org/fhir/StructureDefinition/variable",
        "valueExpression" => { "name" => name, "language" => language, "expression" => expression } }
    end

    def query(name, text)
      variable(name, text, "application/x-fhir-query")
    end

    def launch_context(name, type)
      { "url" => "#{SDC}launchContext", "extension" => [{ "url" => "name", "valueCoding" => { "code" => name } },
                                                        { "url" => "type", "valueCode" => type }] }
    end

    def template_extract(reference, patch_url: nil)
      parts = [{ "url" => "template", "valueReference" => { "reference" => reference } }]
      parts << { "url" => PATCH_URL, "valueString" => patch_url } if patch_url
      { "url" => "#{SDC}templateExtract", "extension" => parts }
    end

    # A FHIRPath Patch template that adds to `path`.
    def patch_template(id, path)
      parts = [{ "name" => "type", "valueCode" => "add" }, { "name" => "path", "valueString" => path }]
      { "resourceType" => "Parameters", "id" => id, "parameter" => [{ "name" => "operation", "part" => parts }] }
    end

    # A group of `resource` named `name`, with a `<name>_<kind>` test per kind in `tests`, `{ kind => details }`.
    def group(name, resource, tests = {}, **attributes)
      group = build_group_metadata(name:, resource:, title: name.capitalize, profile_name: name.capitalize,
                                   profile_url: "#{PROFILE}#{name}", **attributes)
      tests.each do |kind, details|
        group.add_test(id: "#{name}_#{kind}", file_name: "#{name}_#{kind}.rb", kind: kind.to_s, **details)
      end
      group
    end

    def patient_group(tests = { read: {} }, **attributes)
      group("patient", "Patient", tests, **attributes)
    end

    # A form that opens for a Patient, with these items.
    def patient_form(*items, **fields)
      questionnaire(extension: [launch_context("patient", "Patient")], item: items, **fields)
    end

    # `{ group => { test id or :group => Markdown } }` for the forms over the groups. `resources` are other IG
    # resources, like the StructureDefinition of a group's profile.
    def descriptions(forms, groups, resources: [])
      ig_resources = Generator::IGResources.new
      [*Array.wrap(forms).map { |form| FHIR::Questionnaire.new(form) }, *resources].each do |resource|
        ig_resources.add(resource)
      end
      QuestionnaireUsage.descriptions(ig_resources:, groups:)
    end

    # The section written for one group: of its test of `kind`, or its summary.
    def section(form, group, kind = nil, **)
      descriptions(form, [group], **).dig(group, kind ? "#{group.name}_#{kind}" : :group).to_s
    end

    # A profile of `type` that fixes its `code`.
    def profile_fixing(group, code, system: "http://loinc.org")
      FHIR::StructureDefinition.new(
        "resourceType" => "StructureDefinition", "url" => group.profile_url, "type" => group.resource,
        "kind" => "resource", "derivation" => "constraint",
        "snapshot" => { "element" => [
          { "id" => group.resource, "path" => group.resource },
          { "id" => "#{group.resource}.code", "path" => "#{group.resource}.code",
            "patternCodeableConcept" => { "coding" => [{ "system" => system, "code" => code }] } }
        ] }
      )
    end
  end

  # One test per kind of source: where its section goes and what it says.
  class QuestionnaireUsageSourcesTest < Minitest::Test
    include QuestionnaireUsageFixtures

    def test_a_launch_context_goes_to_the_read_test_and_its_checked_elements_to_the_must_support_test
      group = patient_group({ read: {}, must_support: {} }, must_supports: { elements: [{ path: "birthDate" }] })
      written = descriptions(patient_form(reading("dob", "Date of birth", "%patient.birthDate")), [group])[group]

      assert_includes written["patient_read"], <<~MARKDOWN
        - **Form**
          - **Launch context patient**: the Patient the form is opened for
            - **Date of birth**: pre-fills the answer; reads birthDate
      MARKDOWN
      assert_includes written["patient_must_support"], "- **Form**\n  - **birthDate**: Date of birth\n"
      assert_includes written[:group], "- **Form**: see the read and Must Support tests"
    end

    def test_a_search_goes_to_the_search_test_by_the_same_parameters_and_items_read_it_through_variables
      group = group("height", "Observation", { search: { search_names: %w[patient code] } })

      assert_includes section(height_form, group, :search), <<~MARKDOWN
        - **Form**
          - **Query ObsHeight**: searches Observation resources
            - Request: Observation?code=8302-2&_sort=-date&patient={{%patient.id}}
            - **Height**: pre-fills the answer; reads value.value (not checked), status (not checked), value.unit (not checked)
      MARKDOWN
    end

    def test_an_include_goes_to_the_include_test_of_the_group_that_searches
      section = include_suite[:role]["role_include"]

      assert_includes section, "fetch Location resources through this search's _include."
      assert_includes section, <<~MARKDOWN
        - **Query Roles**: fetches Location resources through _include=PractitionerRole:location:Location
            - Request: #{ROLE_QUERY}:Location
            - **Clinic**: pre-fills the answer; reads name (not checked)
      MARKDOWN
    end

    def test_the_summaries_of_both_groups_name_an_include
      written = include_suite

      assert_includes written[:location][:group], "- **Form**: see the search with _include in Role test"
      assert_includes written[:role][:group], "it fetches PractitionerRole:location:Location through _include"
    end

    def test_a_template_goes_to_the_create_test
      template = { "resourceType" => "Observation", "id" => "height",
                   "code" => { "coding" => [{ "system" => "http://loinc.org", "code" => "8302-2" }] } }
      form = questionnaire(contained: [template], item: [item("height", "Height", template_extract("#height"))])

      assert_includes section(form, group("height", "Observation", { create: {} }), :create), <<~MARKDOWN
        These questionnaires in the IG create Observation resources from their answers.

        - **Form**
          - **Extraction template height**: creates a new Observation with code http://loinc.org|8302-2 from the answers
            - **Height**: its answers fill the template
      MARKDOWN
    end

    private

    # A form whose item reads a search through two variables.
    def height_form
      questionnaire(
        extension: [query("ObsHeight", "Observation?code=8302-2&_sort=-date&patient={{%patient.id}}"),
                    variable("Latest", "%ObsHeight.entry.resource.where(status = 'final').first()"),
                    variable("Value", "%Latest.value.where(unit = 'cm').value")],
        item: [reading("height", "Height", "%Value.round(0)")]
      )
    end

    # What is written for a PractitionerRole group with an include test and a Location group, by `:role` and
    # `:location`, when a form reads the Locations a role search includes.
    def include_suite
      details = { search_names: ["practitioner"], include_targets: ["Location"] }
      role = group("role", "PractitionerRole", { include: details })
      location = group("location", "Location")
      form = questionnaire(extension: [query("Roles", "#{ROLE_QUERY}:Location")],
                           item: [reading("loc", "Clinic", "%Roles.entry.resource.ofType(Location).first().name")])
      written = descriptions(form, [role, location])
      { role: written[role], location: written[location] }
    end
  end

  # What the two real kits don't exercise in reading a form.
  class QuestionnaireUsageReadingTest < Minitest::Test
    include QuestionnaireUsageFixtures

    def test_an_entry_filter_by_type_and_a_variable_of_the_picked_entries_go_to_the_include
      form = questionnaire(
        extension: [query("Roles", "#{ROLE_QUERY}:Location"),
                    variable("Picked", "%Roles.entry.where(resource is Location)")],
        item: [reading("a", "A", "%Roles.entry.where(resource is Location).resource.name"),
               reading("b", "B", "%Picked.resource.address")]
      )

      section = include_section(form)

      assert_includes section, "- **A**: pre-fills the answer; reads name (not checked)"
      assert_includes section, "- **B**: pre-fills the answer; reads address (not checked)"
    end

    def test_an_include_without_a_target_takes_the_types_the_form_picks
      form = questionnaire(extension: [query("Roles", ROLE_QUERY)],
                           item: [reading("loc", "Clinic", "%Roles.entry.resource.ofType(Location).name")])

      assert_includes include_section(form), "fetches Location resources through _include=PractitionerRole:location"
    end

    def test_an_extension_read_by_its_url_is_named_by_the_end_of_the_url
      form = patient_form(reading("pronouns", "Pronouns", "%patient.extension('http://example.org/pronouns').value"))

      assert_includes section(form, patient_group, :read), "reads extension[pronouns].value (not checked)"
    end

    def test_an_item_reads_what_the_other_chains_of_its_variable_read
      form = questionnaire(
        extension: [query("Meds", "MedicationStatement?patient={{%patient.id}}"),
                    variable("Contained", "%Meds.entry.resource.contained.ofType(Medication)" \
                                          ".where(id in %Meds.entry.resource.medication.reference.replace('#', ''))")],
        item: [reading("med", "Medication", "%Contained.code")]
      )
      group = group("meds", "MedicationStatement", { search: { search_names: %w[patient] } })

      assert_includes section(form, group, :search),
                      "reads contained (not checked), medication.reference (not checked)\n"
    end

    def test_a_filter_on_the_entries_reads_the_elements_of_their_resource
      fhirpath = "%Obs.entry.where(resource.status = 'final').resource.value.value"
      form = questionnaire(extension: [query("Obs", "Observation?patient={{%patient.id}}")],
                           item: [reading("height", "Height", fhirpath)])

      assert_includes observation_search_section(form), "reads value.value (not checked), status (not checked)\n"
    end

    def test_a_filter_that_names_an_extension_by_url_still_reads_the_rest_of_its_condition
      fhirpath = "%patient.extension.where(exists(url='http://example.org/pronouns') and " \
                 "extension.where(url='period').value.end.empty()).extension.where(url='value').value"
      form = patient_form(reading("pronouns", "Pronouns", fhirpath))

      assert_includes section(form, patient_group, :read),
                      "reads extension[pronouns].extension[value].value (not checked), " \
                      "extension[pronouns].extension[period].value.end (not checked)\n"
    end

    def test_a_filter_on_this_reads_the_filtered_element
      form = patient_form(reading("name", "Name", "%patient.name.where($this.use = 'official').family"))

      assert_includes section(form, patient_group, :read), "reads name.family (not checked), name.use (not checked)"
    end

    def test_a_read_by_id_goes_to_the_read_test_and_reads_the_resource_itself
      form = questionnaire(extension: [query("Pat", "Patient/{{%patient.id}}")],
                           item: [reading("dob", "Date of birth", "%Pat.birthDate")])

      assert_includes section(form, patient_group, :read), <<~MARKDOWN
        - **Query Pat**: reads one Patient by id
            - Request: Patient/{{%patient.id}}
            - **Date of birth**: pre-fills the answer; reads birthDate (not checked)
      MARKDOWN
    end

    def test_a_compartment_search_also_searches_by_its_compartment
      form = questionnaire(extension: [query("Obs", "Patient/{{%patient.id}}/Observation?code=8302-2")],
                           item: [reading("status", "Status", "%Obs.entry.resource.first().status")])
      group = group("height", "Observation", { search: { search_names: %w[code patient] } })

      assert_includes section(form, group, :search), "- **Query Obs**: searches Observation resources"
    end

    def test_forms_without_a_url_are_named_by_their_id_and_stay_apart
      forms = %w[a b].map do |id|
        patient_form(reading("dob", "Date of birth", "%patient.birthDate"), url: nil, title: nil, id:)
      end

      summary = section(forms, patient_group)

      assert_includes summary, "- **a**: see the read test\n- **b**: see the read test"
    end

    private

    def observation_search_section(form)
      section(form, group("obs", "Observation", { search: { search_names: %w[patient] } }), :search)
    end

    # The section of the include test a PractitionerRole group has for its Locations.
    def include_section(form)
      role = group("role", "PractitionerRole", { include: { include_targets: ["Location"] } })
      descriptions(form, [role, group("location", "Location")]).dig(role, "role_include").to_s
    end
  end

  # What tracing leaves out, and what it says about it.
  class QuestionnaireUsageSkipsTest < Minitest::Test
    include QuestionnaireUsageFixtures

    def test_an_expression_that_does_not_parse_is_skipped_and_the_rest_is_traced
      form = patient_form(reading("bad", "Bad", "%%bad(("), reading("dob", "Date of birth", "%patient.birthDate"))

      assert_output(/tracing: skipping FHIRPath "%%bad\(\("/) do
        assert_includes section(form, patient_group, :read), "- **Date of birth**"
      end
    end

    def test_a_variable_used_before_its_definition_is_not_traced
      form = patient_form(reading("a", "A", "%Early"), reading("b", "B", "%Late.gender"))
      form["extension"].push(variable("Early", "%Late.birthDate"), variable("Late", "%patient"))

      assert_output(/tracing: untraced Form variable Early on root: it uses Late, defined after it/) do
        section = section(form, patient_group, :read)

        assert_includes section, "- **B**: pre-fills the answer; reads gender"
        refute_includes section, "- **A**"
      end
    end

    def test_a_template_reference_without_a_contained_resource_is_skipped
      form = questionnaire(item: [item("height", "Height", template_extract("#missing"))])

      assert_output(/skipping Form templateExtract #missing on height: no contained resource #missing/) do
        assert_empty descriptions(form, [patient_group])
      end
    end

    def test_an_include_iterate_and_an_include_of_another_type_are_skipped
      text = "PractitionerRole?_include:iterate=Location:partof&_include=Location:organization"
      form = questionnaire(extension: [query("Roles", text)])

      assert_output(/skipping _include:iterate=Location:partof in Form query Roles: only _include of Practi/) do
        descriptions(form, [group("role", "PractitionerRole", { read: {} })])
      end
    end

    def test_a_query_for_a_code_the_only_profile_fixes_otherwise_is_unresolved
      group = group("height", "Observation", { read: {} })
      form = questionnaire(extension: [query("Weight", "Observation?code=29463-7")],
                           item: [reading("w", "Weight", "%Weight.entry.resource.value")])

      assert_output(%r{the Observation profile fixes code=http://loinc.org\|8302-2, not code=29463-7}) do
        assert_empty descriptions(form, [group], resources: [profile_fixing(group, "8302-2")])
      end
    end

    def test_tracing_before_the_test_generators_raises
      error = assert_raises(RuntimeError) { descriptions(patient_form, [patient_group({})]) }

      assert_match(/must run after the test generators/, error.message)
    end
  end

  # What the two real kits don't exercise in the sections.
  class QuestionnaireUsageWritingTest < Minitest::Test
    include QuestionnaireUsageFixtures

    def test_a_template_on_the_root_fills_from_the_whole_form
      form = questionnaire(contained: [{ "resourceType" => "Patient", "id" => "new" }],
                           extension: [template_extract("#new")])

      assert_includes section(form, patient_group({ create: {} }), :create), <<~MARKDOWN
        - **Extraction template new**: creates a new Patient from the answers
            - Its answers come from the whole form
      MARKDOWN
    end

    def test_a_patch_template_falls_back_to_the_plain_update_test
      form = questionnaire(contained: [patch_template("patch", "Patient.name")],
                           item: [item("name", "Name", template_extract("#patch", patch_url: "'Patient/' + %id"))])

      section = section(form, patient_group({ update: { option: "update" } }), :update)

      assert_includes section, "These questionnaires in the IG update existing Patient resources from their answers."
      assert_includes section, "- **Extraction template patch**: updates an existing Patient with a FHIRPath Patch"
    end

    def test_a_patch_template_ignores_an_update_test_that_creates_a_resource
      form = questionnaire(contained: [patch_template("patch", "Patient.name")],
                           item: [item("name", "Name", template_extract("#patch", patch_url: "'Patient/' + %id"))])
      group = patient_group({ update: { option: "new" } })
      written = descriptions(form, [group])[group]

      assert_nil written["patient_update"]
      assert_includes written[:group], "**Not tested by this group**"
    end

    def test_a_source_lists_25_items_and_counts_the_rest
      items = (1..26).map { |number| reading("i#{number}", "Item #{number}", "%patient.birthDate") }

      section = section(patient_form(*items), patient_group, :read)

      assert_includes section, "- **Item 25**"
      refute_includes section, "- **Item 26**"
      assert_includes section, "    - and 1 more items\n"
    end

    def test_an_element_lists_10_items_and_counts_the_rest
      items = (1..11).map { |number| reading("i#{number}", "Item #{number}", "%patient.birthDate") }
      group = patient_group({ must_support: {} }, must_supports: { elements: [{ path: "birthDate" }] })

      assert_includes section(patient_form(*items), group, :must_support), "Item 9, Item 10, and 1 more\n"
    end

    def test_forms_with_the_same_title_show_their_version
      forms = %w[1.0 2.0].map do |version|
        patient_form(reading("dob", "Date of birth", "%patient.birthDate"), version:)
      end

      summary = section(forms, patient_group)

      assert_includes summary, "- **Form, version 1.0**: see the read test\n- **Form, version 2.0**: see the read test"
    end
  end

  # GroupGenerator writes what QuestionnaireUsage returns into the group file.
  class QuestionnaireUsageGroupFileTest < Minitest::Test
    include QuestionnaireUsageFixtures

    def setup
      @dir = Dir.mktmpdir
      FileUtils.mkdir_p(File.join(@dir, "patient"))
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def test_a_kit_subclass_with_a_three_argument_initialize_still_generates
      group = build_group_metadata(tests: [{ id: "example_patient_read_test", file_name: "patient_read_test.rb" }])
      subclass = Class.new(Generator::GroupGenerator) do
        def initialize(group_metadata, base_output_dir, ig_metadata)
          super
          @kit_option = true
        end
      end

      added = { group => { group: "Usage" } }

      with_config_keeper { subclass.generate(build_ig_metadata(groups: [group]), @dir, added) }

      assert_includes File.read(File.join(@dir, "patient_group.rb")), "Usage"
    end

    def test_tracing_runs_over_the_groups_in_the_order_their_files_are_written
      groups = [group("height", "Observation"), patient_group]
      generator = Generator.new(nil)
      generator.ig_metadata = build_ig_metadata(groups:)
      traced = nil

      with_config_keeper({ "configs" => { "generic" => { "questionnaire_usage_tracing" => true } } }) do
        QuestionnaireUsage.stub(:descriptions, ->(**given) { traced = given[:groups] }) do
          generator.generate_questionnaire_usage
        end
      end

      assert_equal groups.reverse, traced
    end

    def test_recorded_test_kinds_are_read_only_through_test_kind
      refute_respond_to patient_group, :test_kinds
    end

    def test_added_text_is_escaped_so_the_group_file_stays_valid_ruby
      group = build_group_metadata(tests: [{ id: "example_patient_read_test", file_name: "patient_read_test.rb" }])
      added = { group => { :group => "Usage (see \\ and \#{x}, \#@y, \#$z)",
                           "example_patient_read_test" => "Read (one)" } }

      with_config_keeper { Generator::GroupGenerator.generate(build_ig_metadata(groups: [group]), @dir, added) }
      path = File.join(@dir, "patient_group.rb")

      assert RubyVM::InstructionSequence.compile_file(path)
      assert_includes File.read(path), "Usage \\(see \\\\ and \\\#{x}, \\\#@y, \\\#$z\\)"
      assert_includes File.read(path), "test from: :example_patient_read_test do"
      assert_includes File.read(path), "Read \\(one\\)"
    end
  end
end
