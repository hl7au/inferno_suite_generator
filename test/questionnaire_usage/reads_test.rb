# frozen_string_literal: true

require_relative "support"
require "minitest/mock"

# What tracing reads from the questionnaires, through `Tracer#trace`: a form
# goes in, and the trace entries of each profile come out.
module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Verifies `Tracer` finds the x-fhir-query variables that link a
    # questionnaire to a profile, and the items that use them.
    class ReadsQueryTest < Minitest::Test
      include FormFixtures

      def test_a_root_variable_used_by_an_item
        form = questionnaire(
          extension: [query_variable("ObsBodyHeight", HEIGHT_QUERY)],
          item: [item("height", "Height",
                      expression("initialExpression", "%ObsBodyHeight.entry.resource.first().value.value"))]
        )

        traces = trace(form)

        assert_equal [BODY_HEIGHT], traces.keys
        assert_equal height_entry, described(traces[BODY_HEIGHT].sole, "Observation")
      end

      def test_an_item_variable_is_used_only_within_that_item
        entry = trace(weight_in_a_group_form)[BODY_WEIGHT].first

        assert_equal ["weight"], link_ids(entry)
        assert_equal ["value"], reads(entry)
      end

      def test_a_variable_that_no_item_uses_still_gets_an_entry
        form = questionnaire(extension: [query_variable("ObsBodyHeight", HEIGHT_QUERY)],
                             item: [item("height", "Height")])
        entry = trace(form)[BODY_HEIGHT].first

        assert_empty entry.item_uses
      end

      def test_a_read_links_to_every_group_of_its_type_and_reads_the_resource_itself
        traces = trace(patient_read_form,
                       profiles: { AU_CORE_PATIENT => profile("Patient"), AU_BASE_PATIENT => profile("Patient") })
        entry = traces[AU_CORE_PATIENT].first

        assert_equal [AU_CORE_PATIENT, AU_BASE_PATIENT], traces.keys
        assert_equal "**Query PatientRead**: reads one Patient by id", entry.heading("Patient")
        assert_equal ["birthDate"], reads(entry)
        assert_equal ["dob"], link_ids(entry)
      end

      def test_a_module_form_logs_the_assemble_context_names_it_reads
        form = questionnaire(
          extension: [assemble_context("ObsBodyWeightLatest"), assemble_context("age")],
          item: [item("weight", "Weight", expression("initialExpression", "%ObsBodyWeightLatest.value.value"))]
        )

        assert_output(/Management Plan reads ObsBodyWeightLatest from the form it is assembled into/) do
          assert_empty trace(form)
        end
      end

      def test_a_query_for_a_type_without_a_group_is_untraced
        form = questionnaire(extension: [query_variable("Conditions", "Condition?patient={{%patient.id}}")])

        assert_output(/untraced .* query Conditions/) { assert_empty trace(form) }
      end

      private

      def height_entry
        { heading: "**Query ObsBodyHeight**: searches Observation resources", request: HEIGHT_QUERY,
          item_uses: [ItemUse.new(link_id: "height", text: "Height", extension: "initialExpression",
                                  reads: ["value.value"])] }
      end

      # A read of the patient, so `%PatientRead` is the Patient, not a Bundle.
      def patient_read_form
        questionnaire(
          extension: [query_variable("PatientRead", "Patient/{{%patient.id}}")],
          item: [item("dob", "Date of birth", expression("initialExpression", "%PatientRead.birthDate"))]
        )
      end

      # `ObsBodyWeight` is defined on the `vitals` group and used by its child
      # `weight`. The sibling `other` reads it too, but is out of its scope.
      def weight_in_a_group_form
        weight = item("weight", "Weight", expression("calculatedExpression", "%ObsBodyWeight.entry.resource.value"))
        other = item("other", "Other", expression("initialExpression", "%ObsBodyWeight.entry.resource.status"))
        vitals = item("vitals", "Vitals", query_variable("ObsBodyWeight", WEIGHT_QUERY), children: [weight])
        questionnaire(item: [vitals, other])
      end
    end

    # Verifies `Tracer` traces `_include` targets as their own entries, and
    # routes each chain to the include or the query entry by its type.
    class ReadsIncludeTest < Minitest::Test
      include FormFixtures

      MEDICATION_STATEMENT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-medicationstatement"
      MEDICATION = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-medication"
      PRACTITIONER_ROLE = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-practitionerrole"
      LOCATION = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-location"
      MEDS_QUERY = "MedicationStatement?patient={{%patient.id}}&status=active&_include=MedicationStatement:medication"
      LOCATION_NAME_EXPRESSION = "%PractitionerRoleLocation.entry.resource.ofType(Location).first().name"
      MEDS_EXPRESSION = "%MedicationStatement.entry.resource.ofType(Medication)" \
                        ".where(id in %MedicationStatement.entry.resource.medication.select(reference))"

      def test_an_include_entry_on_the_target_group_from_the_search_parameter
        traces = trace(medications_form, profiles: suite_profiles, resources: [medication_param])

        assert_equal medication_entry, described(traces[MEDICATION].sole, "Medication")
      end

      def test_a_chain_without_of_type_in_the_same_item_goes_to_the_query_entry
        traces = trace(medications_form, profiles: suite_profiles, resources: [medication_param])
        entry = traces[MEDICATION_STATEMENT].first

        assert_kind_of TraceEntry::Query, entry
        assert_equal ["medications"], link_ids(entry)
        assert_equal ["medication", "medication.reference"], reads(entry)
      end

      def test_an_explicit_target_type
        entry = trace(location_form("PractitionerRole:location:Location"), profiles: suite_profiles)[LOCATION].first

        assert_equal ["name"], reads(entry)
        assert_equal ["location"], link_ids(entry)
      end

      def test_a_target_type_from_of_type_in_the_form
        entry = trace(location_form("PractitionerRole:location"), profiles: suite_profiles)[LOCATION].first

        assert_equal "**Query PractitionerRoleLocation**: fetches Location resources through " \
                     "_include=PractitionerRole:location", entry.heading("Location")
      end

      def test_an_include_without_a_search_parameter_or_of_type_is_unresolved
        query = location_query("PractitionerRole:location")
        form = questionnaire(extension: [query_variable("PractitionerRoleLocation", query)])

        assert_output(/unresolved .* include PractitionerRole:location: no target type/) do
          refute trace(form, profiles: suite_profiles).key?(LOCATION)
        end
      end

      def test_an_include_of_the_query_own_type_leaves_its_chains_with_the_query_entry
        query_entry, include_entry = trace(own_type_include_form)[BODY_HEIGHT].partition do |entry|
          entry.is_a?(TraceEntry::Query)
        end.map(&:first)

        assert_equal [["height"], ["value"]], [link_ids(query_entry), reads(query_entry)]
        assert_empty include_entry.item_uses
      end

      def test_an_include_iterate_and_an_include_of_another_type_are_skipped
        query = "#{MEDS_QUERY}&_include:iterate=Medication:manufacturer&_include=Medication:manufacturer"
        form = questionnaire(extension: [query_variable("MedicationStatement", query)])

        out, = capture_io { trace(form, profiles: suite_profiles, resources: [medication_param]) }

        assert_match(/skipping _include:iterate=Medication:manufacturer/, out)
        assert_match(/skipping _include=Medication:manufacturer in .*: only _include of MedicationStatement/, out)
      end

      private

      def suite_profiles
        { MEDICATION_STATEMENT => profile("MedicationStatement"), MEDICATION => profile("Medication"),
          PRACTITIONER_ROLE => profile("PractitionerRole"), LOCATION => profile("Location") }
      end

      def medication_param
        FHIR::SearchParameter.new("resourceType" => "SearchParameter", "url" => "http://example.org/medication",
                                  "name" => "medication", "status" => "active", "code" => "medication",
                                  "base" => ["MedicationStatement"], "type" => "reference", "target" => ["Medication"])
      end

      def medications_form
        questionnaire(extension: [query_variable("MedicationStatement", MEDS_QUERY)],
                      item: [item("medications", "Medications", expression("initialExpression", MEDS_EXPRESSION))])
      end

      def medication_entry
        { heading: "**Query MedicationStatement**: fetches Medication resources through " \
                   "_include=MedicationStatement:medication",
          request: MEDS_QUERY,
          item_uses: [ItemUse.new(link_id: "medications", text: "Medications", extension: "initialExpression",
                                  reads: ["id"])] }
      end

      # A Body Height query that also includes the Observations its results
      # have as members.
      def own_type_include_form
        questionnaire(
          extension: [query_variable("Heights", "Observation?code=8302-2&_include=Observation:has-member:Observation")],
          item: [item("height", "Height",
                      expression("initialExpression", "%Heights.entry.resource.ofType(Observation).value"))]
        )
      end

      def location_query(include)
        "PractitionerRole?practitioner={{%user.id}}&_include=#{include}"
      end

      def location_form(include)
        questionnaire(
          extension: [query_variable("PractitionerRoleLocation", location_query(include))],
          item: [item("location", "Location", expression("initialExpression", LOCATION_NAME_EXPRESSION))]
        )
      end
    end

    # Verifies `Tracer` routes a chain that picks entries with
    # `entry.where(resource is T)` to the include entry of `T`, directly or
    # through an alias of the picked entries.
    class ReadsEntryFilterTest < Minitest::Test
      include FormFixtures

      PRACTITIONER_ROLE = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-practitionerrole"
      LOCATION = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-location"
      QUERY = "PractitionerRole?practitioner={{%user.id}}&_include=PractitionerRole:location:Location"

      def test_an_is_filter_on_entry_routes_a_chain_to_its_include_entry
        traces = location_traces("%PractitionerRoleLocation.entry.where(resource is Location).resource.name")

        assert_equal ["name"], reads(traces[LOCATION].first)
        assert_empty traces[PRACTITIONER_ROLE].first.item_uses
      end

      def test_an_alias_of_filtered_entries_routes_its_chains_to_the_include_entry
        locations = fhirpath_variable("Locations", "%PractitionerRoleLocation.entry.where(resource is Location)")
        traces = location_traces("%Locations.resource.name", variables: [locations])

        assert_equal ["name"], reads(traces[LOCATION].first)
        assert_empty traces[PRACTITIONER_ROLE].first.item_uses
      end

      def test_an_is_call_on_entry_routes_like_an_is_filter
        traces = location_traces("%PractitionerRoleLocation.entry.where(resource.is(FHIR.Location)).resource.name")

        assert_equal ["name"], reads(traces[LOCATION].first)
      end

      def test_an_as_filter_on_entry_picks_no_type
        traces = location_traces("%PractitionerRoleLocation.entry.where(resource as Location).resource.name")

        assert_equal ["name"], reads(traces[PRACTITIONER_ROLE].first)
        assert_empty traces[LOCATION].first.item_uses
      end

      def test_aliases_of_one_picked_entry_and_of_all_entries
        first = fhirpath_variable("First", "%PractitionerRoleLocation.entry.where(resource is Location).first()")
        entries = fhirpath_variable("Entries", "%PractitionerRoleLocation.entry")
        traces = location_traces("%First.resource.name | %Entries.where(resource is Location).resource.address",
                                 variables: [first, entries])

        assert_equal %w[name address], reads(traces[LOCATION].first)
      end

      private

      # The traces of a form whose `location` item reads `fhirpath`.
      def location_traces(fhirpath, variables: [])
        form = questionnaire(extension: [query_variable("PractitionerRoleLocation", QUERY), *variables],
                             item: [item("location", "Location", expression("initialExpression", fhirpath))])
        trace(form, profiles: { PRACTITIONER_ROLE => profile("PractitionerRole"), LOCATION => profile("Location") })
      end
    end

    # Verifies `Tracer` traces an `_include` whose resources the form picks
    # with `where(resourceType = 'T')`, like the 715 Absolute CVD Risk module,
    # which picks the requests and the included Medications in one variable and
    # the Medications out of it again.
    class ReadsMixedIncludeTest < Minitest::Test
      include FormFixtures

      MEDICATION_REQUEST = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-medicationrequest"
      MEDICATION = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-medication"
      QUERY = "MedicationRequest?patient={{%patient.id}}&_include=MedicationRequest:medication"
      MEDS = "%MedicationRequest.entry.resource.where(intent = 'order' or resourceType = 'Medication')"

      def test_a_target_type_from_where_resource_type_in_the_form
        entry = traces[MEDICATION].first

        assert_equal ["code"], reads(entry)
        assert_equal ["insulin"], link_ids(entry)
      end

      def test_untyped_chains_of_a_variable_of_several_types_stay_with_the_query_entry
        entry = traces[MEDICATION_REQUEST].first

        assert_equal ["recent"], link_ids(entry)
        assert_equal %w[authoredOn], reads(entry)
      end

      private

      def traces
        trace(form, profiles: { MEDICATION_REQUEST => profile("MedicationRequest"),
                                MEDICATION => profile("Medication") })
      end

      def form
        questionnaire(
          extension: [query_variable("MedicationRequest", QUERY), fhirpath_variable("meds", MEDS)],
          item: [item("insulin", "Insulin", expression("initialExpression",
                                                       "%meds.where(resourceType = 'Medication' and code.exists())")),
                 item("recent", "Recent", expression("initialExpression",
                                                     "%meds.where(authoredOn > now() - 12 months).exists()"))]
        )
      end
    end

    # Verifies `Tracer` traces `launchContext` resources and the elements the
    # items read from them.
    class ReadsLaunchContextTest < Minitest::Test
      include FormFixtures

      AU_CORE_PRACTITIONER = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-practitioner"

      def test_an_item_reads_an_element_of_the_launch_patient
        form = questionnaire(extension: [launch_context("patient", "Patient")],
                             item: [item("dob", "Date of birth",
                                         expression("initialExpression", "%patient.birthDate.toString()"))])

        assert_equal({ heading: "**Launch context patient**: the Patient the form is opened for", request: nil,
                       item_uses: [ItemUse.new(link_id: "dob", text: "Date of birth", extension: "initialExpression",
                                               reads: ["birthDate"])] },
                     described(trace(form, profiles: patient_profiles)[AU_CORE_PATIENT].sole, "Patient"))
      end

      def test_every_patient_group_gets_the_entry
        form = questionnaire(extension: [launch_context("patient", "Patient")])

        assert_equal [AU_CORE_PATIENT, AU_BASE_PATIENT], trace(form, profiles: patient_profiles).keys
      end

      def test_an_alias_of_the_launch_patient
        recorded_sex = "%patient.extension.where(url = '#{RECORDED_SEX_URL}')"
        form = questionnaire(extension: [launch_context("patient", "Patient"),
                                         fhirpath_variable("RecordedSex", recorded_sex)],
                             item: [item("sex", "Sex", expression("initialExpression", "%RecordedSex.value.code"))])
        entry = trace(form, profiles: patient_profiles)[AU_CORE_PATIENT].first

        assert_equal [["sex"], ["extension[url=#{RECORDED_SEX_URL}].value.code"]], [link_ids(entry), reads(entry)]
      end

      def test_one_entry_per_type_of_the_launch_context
        form = questionnaire(extension: [launch_context("user", "Practitioner", "Patient", value_id: true)],
                             item: [item("author", "Author", expression("initialExpression", "%user.name.text"))])
        traces = trace(form, profiles: patient_profiles.merge(AU_CORE_PRACTITIONER => profile("Practitioner")))

        assert_equal [AU_CORE_PRACTITIONER, AU_CORE_PATIENT, AU_BASE_PATIENT], traces.keys
        assert_equal ["name.text"], reads(traces[AU_CORE_PRACTITIONER].first)
      end

      def test_a_chain_that_picks_one_type_counts_for_that_type_only
        fhirpath = "%user.where(resourceType = 'Practitioner').qualification.code"
        form = questionnaire(extension: [launch_context("user", "Practitioner", "Patient")],
                             item: [item("qualification", "Qualification", expression("initialExpression", fhirpath))])
        traces = trace(form, profiles: patient_profiles.merge(AU_CORE_PRACTITIONER => profile("Practitioner")))

        assert_equal ["qualification.code"], reads(traces[AU_CORE_PRACTITIONER].first)
        assert_empty traces[AU_CORE_PATIENT].first.item_uses
      end

      def test_an_expression_on_the_root_is_a_usage_without_the_narrative_as_text
        form = questionnaire(extension: [launch_context("patient", "Patient"),
                                         expression("itemExtractionContext", "%patient.name")])
               .merge("text" => { "status" => "generated", "div" => "<div>Intake</div>" })
        entry = trace(form, profiles: patient_profiles)[AU_CORE_PATIENT].first

        assert_equal [ItemUse.new(extension: "itemExtractionContext", reads: ["name"])], entry.item_uses
      end

      def test_a_form_without_a_url_is_named_by_its_id
        form = questionnaire(extension: [launch_context("patient", "Patient")]).except("url").merge("id" => "intake")
        entry = trace(form, profiles: patient_profiles)[AU_CORE_PATIENT].first

        assert_equal [nil, "intake", "0.1.0"], entry.form.key
      end

      def test_a_launch_context_without_a_group_for_its_type_is_untraced
        form = questionnaire(extension: [launch_context("encounter", "Encounter")])

        assert_output(/untraced .* launch context encounter: no group for Encounter/) do
          assert_empty trace(form, profiles: patient_profiles)
        end
      end

      private

      def patient_profiles
        { AU_CORE_PATIENT => profile("Patient"), AU_BASE_PATIENT => profile("Patient") }
      end
    end

    # Verifies `Tracer` traces `templateExtract` templates to the profile of the
    # resource they create or patch.
    class ReadsTemplateTest < Minitest::Test
      include FormFixtures

      AU_CORE_CONDITION = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-condition"
      PATCH_URL = "https://smartforms.csiro.au/ig/StructureDefinition/TemplateExtractExtensionPatchRequestUrl"

      def test_an_item_with_a_body_height_template
        form = questionnaire(contained: [body_height_template],
                             item: [item("height", "Height", template_extract("#BodyHeightTemplate"))])

        assert_equal({ heading: "**Extraction template BodyHeightTemplate**: creates a new Observation with code " \
                                "#{LOINC}|8302-2, #{SNOMED}|50373000 from the answers",
                       request: nil,
                       item_uses: [ItemUse.new(link_id: "height", text: "Height", extension: "templateExtract")] },
                     described(trace(form, profiles: suite_profiles)[BODY_HEIGHT].sole, "Observation"))
      end

      def test_a_template_with_a_code_the_only_profile_fixes_otherwise_is_unresolved
        weight = body_height_template.merge("code" => { "coding" => [{ "system" => LOINC, "code" => "29463-7" }] })
        form = questionnaire(contained: [weight],
                             item: [item("height", "Height", template_extract("#BodyHeightTemplate"))])

        assert_output(/unresolved .* templateExtract .*: the Observation profile fixes code=/) do
          assert_empty trace(form, profiles: { BODY_HEIGHT => body_height })
        end
      end

      def test_a_patch_template_targets_the_type_in_its_operation_paths
        form = questionnaire(contained: [condition_patch_template(path: "Condition")],
                             item: [item("condition", "Condition", condition_patch_extract)])
        entry = trace(form, profiles: suite_profiles)[AU_CORE_CONDITION].first

        assert_equal "**Extraction template ConditionPatchTemplate**: updates an existing Condition with a " \
                     "FHIRPath Patch", entry.heading("Condition")
      end

      def test_a_patch_template_without_paths_targets_the_type_in_its_request_url
        form = questionnaire(contained: [condition_patch_template],
                             item: [item("condition", "Condition", condition_patch_extract)])

        assert_equal "ConditionPatchTemplate", trace(form, profiles: suite_profiles)[AU_CORE_CONDITION].first.name
      end

      def test_a_template_on_the_root_has_no_items
        form = questionnaire(contained: [body_height_template], extension: [template_extract("#BodyHeightTemplate")])
        entry = trace(form, profiles: suite_profiles)[BODY_HEIGHT].first

        assert_empty entry.item_uses
      end

      def test_a_reference_to_a_missing_contained_resource_is_skipped
        form = questionnaire(item: [item("height", "Height", template_extract("#Missing"))])

        assert_output(/skipping .* templateExtract #Missing on height: no contained resource #Missing/) do
          assert_empty trace(form, profiles: suite_profiles)
        end
      end

      private

      def suite_profiles
        observation_profiles.merge(AU_CORE_CONDITION => profile("Condition"))
      end

      def template_extract(reference, patch_url: nil)
        parts = [{ "url" => "template", "valueReference" => { "reference" => reference } }]
        parts << { "url" => PATCH_URL, "valueString" => patch_url } if patch_url
        { "url" => "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-templateExtract",
          "extension" => parts }
      end

      def condition_patch_extract
        template_extract("#ConditionPatchTemplate",
                         patch_url: "'Condition/' + item.where(linkId='conditionId').answer.value")
      end

      def body_height_template
        { "resourceType" => "Observation", "id" => "BodyHeightTemplate", "status" => "final",
          "category" => [{ "coding" => [{ "system" => OBSERVATION_CATEGORY, "code" => "vital-signs" }] }],
          "code" => { "coding" => [{ "system" => LOINC, "code" => "8302-2" },
                                   { "system" => SNOMED, "code" => "50373000" }] } }
      end

      # A FHIRPath Patch `Parameters`, with one `add` operation on `path` when
      # given.
      def condition_patch_template(path: nil)
        parts = [{ "name" => "type", "valueCode" => "add" }, { "name" => "name", "valueString" => "clinicalStatus" }]
        parts << { "name" => "path", "valueString" => path } if path
        { "resourceType" => "Parameters", "id" => "ConditionPatchTemplate",
          "parameter" => [{ "name" => "operation", "part" => parts }] }
      end
    end

    # Verifies `Tracer` follows variable chains: items that read a query
    # through `text/fhirpath` variables count as its users.
    class ReadsAliasTest < Minitest::Test
      include FormFixtures

      # The GP CCMP chain: `ObsBodyHeight` -> `ObsBodyHeightLatest` ->
      # `ObsBodyHeightValue`, read by the `height` item.
      def test_an_item_reads_a_query_through_a_chain_of_aliases
        entry = trace(height_chain_form)[BODY_HEIGHT].first

        assert_equal [ItemUse.new(link_id: "height", text: "Height", extension: "initialExpression",
                                  reads: ["value.value"])],
                     entry.item_uses
      end

      def test_users_of_an_alias_that_stops_at_select_add_no_path
        form = questionnaire(
          extension: [query_variable("ObsBodyHeight", HEIGHT_QUERY),
                      fhirpath_variable("HeightCodes", "%ObsBodyHeight.entry.resource.code.select(coding.code)")],
          item: [item("codes", "Codes", expression("initialExpression", "%HeightCodes.first().length()"))]
        )
        entry = trace(form)[BODY_HEIGHT].first

        assert_equal [["codes"], []], [link_ids(entry), reads(entry)]
      end

      def test_an_alias_on_an_item_is_not_visible_to_a_sibling
        entry = trace(alias_in_a_group_form)[BODY_HEIGHT].first

        assert_equal [ItemUse.new(link_id: "height", text: "Height", extension: "initialExpression", reads: ["value"])],
                     entry.item_uses
      end

      def test_each_expression_is_parsed_once
        parsed = Hash.new(0)
        parse = Fhirpath::Parser.method(:parse)
        counting_parse = lambda do |expression|
          parsed[expression] += 1
          parse.call(expression)
        end

        Fhirpath::Parser.stub(:parse, counting_parse) { trace(height_chain_form) }

        assert_equal [1], parsed.values.uniq
      end

      def test_aliases_that_reference_each_other_do_not_loop
        form = questionnaire(extension: [query_variable("ObsBodyHeight", HEIGHT_QUERY),
                                         fhirpath_variable("A", "%B | %ObsBodyHeight.entry.resource"),
                                         fhirpath_variable("B", "%A")],
                             item: [item("height", "Height", expression("initialExpression", "%B.value"))])

        assert_equal ["height"], link_ids(trace(form)[BODY_HEIGHT].first)
      end

      private

      def height_chain_form
        latest = fhirpath_variable("ObsBodyHeightLatest",
                                   "%ObsBodyHeight.entry.resource.where(status = 'final').first()")
        value = fhirpath_variable("ObsBodyHeightValue", "%ObsBodyHeightLatest.value.where(unit = 'cm').value")
        questionnaire(
          extension: [query_variable("ObsBodyHeight", HEIGHT_QUERY), latest, value],
          item: [item("height", "Height", expression("initialExpression", "%ObsBodyHeightValue.round(0)"))]
        )
      end

      # `HeightLatest` is defined on the `vitals` group. Its child `height` reads
      # it; the sibling `other` reads the same name, but can't see it.
      def alias_in_a_group_form
        height = item("height", "Height", expression("initialExpression", "%HeightLatest.value"))
        other = item("other", "Other", expression("initialExpression", "%HeightLatest.status"))
        vitals = item("vitals", "Vitals", fhirpath_variable("HeightLatest", "%ObsBodyHeight.entry.resource.first()"),
                      children: [height])
        questionnaire(extension: [query_variable("ObsBodyHeight", HEIGHT_QUERY)], item: [vitals, other])
      end
    end

    # Verifies which element paths an item's FHIRPath reads, using expressions
    # from the 715 Health Check, GP CCMP and 715 Absolute CVD Risk forms.
    class ReadsExpressionTest < Minitest::Test
      include FormFixtures

      SEX = "extension[url=#{RECORDED_SEX_URL}]".freeze

      # From `%patient`, a resource: fhirpath => elements read.
      RESOURCE_READS = {
        "%patient.birthDate.toString()" => ["birthDate"],
        "%`patient`.birthDate" => ["birthDate"],
        "%patient.telecom.where(system='phone').value" => ["telecom.value", "telecom.system"],
        "%patient.extension.where(url='#{RECORDED_SEX_URL}').exists()" => [SEX],
        "%patient.extension('#{RECORDED_SEX_URL}').exists()" => [SEX],
        "%patient.extension.where(exists(url='#{RECORDED_SEX_URL}' and extension.where(url='type').exists()) " \
        "and (url != 'x')).extension.where(url='value').value" => ["#{SEX}.extension[url=value].value"],
        "%patient.extension.where(url != 'http://x/a').value" => ["extension.value", "extension.url"],
        "%patient.extension.where(extension.where(url='type').exists()).value" =>
          ["extension.value", "extension.extension[url=type]"],
        "%patient.name.select(given.first() + ' ' + family)" => ["name", "name.given", "name.family"],
        "%patient.value.ofType(Quantity).value" => ["value"],
        "%patient.generalPractitioner.resolve().name.given" => ["generalPractitioner"],
        "%patient.contact.descendants().value" => ["contact"],
        "%patient.children().code" => [],
        "%patient.where($this.id.exists() and iif(intent = 'order', authoredOn > now(), false))" =>
          %w[id intent authoredOn],
        "%patient.where(id in %orders.medicationReference.select(reference.replace('Medication/', '')))" => ["id"],
        "%patient.contained.where(resourceType = 'Medication').where(code.exists())" => ["contained", "contained.code"]
      }.freeze

      # From `%q`, a query's Bundle: fhirpath => elements read.
      BUNDLE_READS = {
        "%q.entry.resource.where(status = 'final' or status = 'amended').first()" => ["status"],
        "%q.entry.first().resource.code" => ["code"],
        "%q.entry.where(resource is Observation).resource.code" => ["code"],
        "%q.entry.where(resource.is(FHIR.Observation)).resource" => [],
        "%q.entry.resource.where(clinicalStatus.coding.exists(code = 'active'))" \
        ".where(verificationStatus.coding.all(code.empty() or code = 'confirmed'))" =>
          ["clinicalStatus.coding", "clinicalStatus.coding.code", "verificationStatus.coding",
           "verificationStatus.coding.code"],
        "%q.total > 0" => [],
        "%q.entry.count()" => [],
        "%q.entry.fullUrl" => []
      }.freeze

      def test_the_paths_an_item_reads_from_a_resource
        RESOURCE_READS.each do |fhirpath, reads|
          entry = patient_entry(fhirpath)

          assert_equal [["item"], reads], [link_ids(entry), reads(entry)], fhirpath
        end
      end

      def test_the_paths_an_item_reads_from_a_bundle
        BUNDLE_READS.each do |fhirpath, reads|
          entry = bundle_entry(fhirpath)

          assert_equal [["item"], reads], [link_ids(entry), reads(entry)], fhirpath
        end
      end

      def test_a_name_inside_a_string_is_not_a_use
        assert_empty patient_entry("'%patient'").item_uses
      end

      def test_an_expression_that_does_not_parse_is_skipped
        assert_output(/skipping FHIRPath "%%bad\(\("/) { assert_empty patient_entry("%%bad((").item_uses }
      end

      private

      def patient_entry(fhirpath)
        form = questionnaire(extension: [launch_context("patient", "Patient")], item: [reading_item(fhirpath)])
        trace(form, profiles: { AU_CORE_PATIENT => profile("Patient") })[AU_CORE_PATIENT].sole
      end

      def bundle_entry(fhirpath)
        form = questionnaire(extension: [query_variable("q", "Observation?code=8302-2")],
                             item: [reading_item(fhirpath)])
        trace(form, profiles: { BODY_HEIGHT => body_height })[BODY_HEIGHT].sole
      end

      def reading_item(fhirpath)
        item("item", "Item", expression("initialExpression", fhirpath))
      end
    end

    # Verifies which profiles a query links to, from its resource type and the
    # `code` and `category` values it searches by and its profiles fix.
    class ReadsQueryMatchTest < Minitest::Test
      include FormFixtures

      # Over the Observation profiles: query => the profiles it links to.
      MATCHES = {
        "Observation?code=8302-2" => [BODY_HEIGHT],
        "Observation?code=#{LOINC}|29463-7" => [BODY_WEIGHT],
        "Observation?code=http%3A%2F%2Floinc.org%7C8302-2" => [BODY_HEIGHT],
        "Observation?code=8302-2,8306-3&_sort=-date" => [BODY_HEIGHT],
        "Observation?patient={{'Patient/' & %patient.id}}&code=8302-2" => [BODY_HEIGHT],
        "Patient/{{%patient.id}}/Observation?code=8302-2" => [BODY_HEIGHT],
        "Observation/$lastn?code=8302-2" => [BODY_HEIGHT]
      }.freeze

      # Over the Observation profiles: query => what the log says.
      UNRESOLVED = {
        "Observation?code=1234-5" => "no Observation profile matches code=1234-5",
        "Observation?code=#{SNOMED}|8302-2" => "no Observation profile matches code=#{SNOMED}|8302-2",
        "Observation?code={{%codes}}" => "no Observation profile matches (no codes)",
        "Observation?code=50%" => "no Observation profile matches code=50%",
        "Unknown/thing?code=1" => "no group for thing"
      }.freeze

      def test_a_query_links_to_the_profiles_that_fix_its_codes
        MATCHES.each { |query, expected| assert_equal expected, matched(query), query }
      end

      def test_a_query_no_profile_matches_is_unresolved
        UNRESOLVED.each do |query, message|
          assert_output(/#{Regexp.escape(message)}/) { assert_nil matched(query) }
        end
      end

      def test_a_category_query_links_to_every_profile_with_that_category
        assert_output(/matches several profiles/) do
          assert_equal [BODY_HEIGHT, BODY_WEIGHT], matched("Observation?category=vital-signs")
        end
      end

      def test_the_only_profile_of_the_type_matches_unless_it_fixes_another_code
        only = { BODY_HEIGHT => body_height }

        assert_equal [BODY_HEIGHT], matched("Observation?code=8302-2", only)
        assert_equal [BODY_HEIGHT], matched("Observation?patient={{%patient.id}}", only)
        assert_output(/the Observation profile fixes code=\S+\|8302-2, .*, not code=29463-7/) do
          assert_nil matched("Observation?code=29463-7", only)
        end
      end

      def test_only_an_id_after_the_type_makes_a_read
        patient = { AU_CORE_PATIENT => profile("Patient") }

        assert_equal [true], read_flags("Patient/{{%patient.id}}", patient)
        assert_equal [false], read_flags("Patient/_search?family=x", patient)
        assert_equal [false], read_flags("Patient/{{%patient.id}}/$everything", patient)
        assert_equal [false], read_flags("Observation/$lastn?code=8302-2")
      end

      private

      # The profiles the query links to, `nil` when it links to none.
      def matched(query, profiles = observation_profiles)
        traces = trace(questionnaire(extension: [query_variable("Q", query)]), profiles:)
        traces.keys unless traces.empty?
      end

      def read_flags(query, profiles = observation_profiles)
        trace(questionnaire(extension: [query_variable("Q", query)]), profiles:).values.flatten.map do |entry|
          entry.query.read?
        end.uniq
      end
    end
  end
end
