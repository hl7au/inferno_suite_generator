# frozen_string_literal: true

require_relative "test_helper"
require "active_support/core_ext/object/blank"
require "fhir_models"
require "inferno_suite_generator/core/group_metadata"
require "inferno_suite_generator/core/ig_resources"
require "inferno_suite_generator/questionnaire_usage_tracing/ast"
require "inferno_suite_generator/questionnaire_usage_tracing/profile_matcher"
require "inferno_suite_generator/questionnaire_usage_tracing/tracer"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # Verifies `Ast` reads `%Name` references and element paths from the
    # FHIRPath AST, using expressions from the 715 Health Check and GP CCMP forms.
    class AstTest < Minitest::Test
      RECORDED_SEX_URL = "http://hl7.org/fhir/StructureDefinition/individual-recordedSexOrGender"

      def test_references_returns_the_external_constant_names
        assert_equal ["ObsBodyHeight"], Ast.references("%ObsBodyHeight.entry")
      end

      def test_references_lists_each_name_once
        assert_equal %w[A B], Ast.references("%A.x | %B.where(y = %A.z)")
      end

      def test_references_strips_backticks
        assert_equal ["vs-x"], Ast.references("%`vs-x`.code")
      end

      def test_references_ignores_a_name_inside_a_string_literal
        assert_empty Ast.references("'%Foo'")
      end

      def test_references_returns_empty_and_logs_on_bad_syntax
        assert_output(/skipping FHIRPath/) { assert_empty Ast.references("%%bad((") }
      end

      def test_paths_returns_empty_and_logs_on_bad_syntax
        assert_output(/skipping FHIRPath/) { assert_empty Ast.paths("%%bad((", "bad", bundle: false) }
      end

      def test_paths_ignores_chains_from_other_names
        assert_empty Ast.paths("%patient.birthDate", "user", bundle: false)
      end

      def test_paths_drops_function_calls
        assert_paths [{ type: nil, path: "birthDate", stopped: false }],
                     "%patient.birthDate.toString()", "patient"
      end

      def test_paths_drops_a_where_filter_on_a_member
        assert_paths [{ type: nil, path: "telecom.value", stopped: false }],
                     "%patient.telecom.where(system='phone').value", "patient"
      end

      def test_paths_keeps_the_url_of_an_extension_filter
        assert_paths [{ type: nil, path: "extension[url=#{RECORDED_SEX_URL}]", stopped: false }],
                     "%patient.extension.where(url='#{RECORDED_SEX_URL}').exists()", "patient"
      end

      def test_paths_keeps_the_url_of_the_extension_function
        assert_paths [{ type: nil, path: "extension[url=#{RECORDED_SEX_URL}]", stopped: false }],
                     "%patient.extension('#{RECORDED_SEX_URL}').exists()", "patient"
      end

      def test_paths_gives_an_empty_path_for_a_chain_that_only_picks_the_resource
        assert_paths [{ type: nil, path: "", stopped: false }],
                     "%ObsBodyHeight.entry.resource.where(status = 'final' or status = 'amended').first()",
                     "ObsBodyHeight", bundle: true
      end

      def test_paths_stops_at_select
        assert_paths [{ type: nil, path: "name", stopped: true }],
                     "%user.name.select(given.first() + ' ' + family)", "user"
      end

      def test_paths_stops_at_of_type_outside_a_bundle
        assert_paths [{ type: nil, path: "value", stopped: true }],
                     "%obs.value.ofType(Quantity).value", "obs"
      end

      def test_paths_reads_the_type_of_a_bundle_chain_from_of_type
        assert_paths [{ type: "Location", path: "", stopped: false }],
                     "%PractitionerRoleLocation.entry.resource.ofType(Location)",
                     "PractitionerRoleLocation", bundle: true
      end

      def test_paths_reads_the_query_own_type_from_of_type
        assert_paths [{ type: "MedicationStatement", path: "", stopped: false }],
                     "%MedicationStatement.entry.resource.ofType(MedicationStatement)",
                     "MedicationStatement", bundle: true
      end

      def test_paths_finds_chains_nested_in_function_arguments
        expression = "%MedicationStatement.entry.resource.ofType(Medication)" \
                     ".where(id in %MedicationStatement.entry.resource.medication.select(reference))"

        assert_paths [{ type: "Medication", path: "", stopped: false },
                      { type: nil, path: "medication", stopped: true }],
                     expression, "MedicationStatement", bundle: true
      end

      def test_paths_reads_an_alias_chain
        assert_paths [{ type: nil, path: "value.value", stopped: false }],
                     "%ObsBodyHeightLatest.value.where(unit = 'cm').value", "ObsBodyHeightLatest"
      end

      private

      def assert_paths(expected, expression, name, bundle: false)
        assert_equal expected, Ast.paths(expression, name, bundle:)
      end
    end

    # Profiles and helpers shared by the `ProfileMatcher` tests. Body Height
    # fixes its code with a `patternCodeableConcept`, Body Weight with
    # `fixedCode` and `fixedUri` on a coding slice, like the real AU Core profiles.
    module ProfileMatcherFixtures
      LOINC = "http://loinc.org"
      OBSERVATION_CATEGORY = "http://terminology.hl7.org/CodeSystem/observation-category"
      BODY_HEIGHT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-bodyheight"
      BODY_WEIGHT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-bodyweight"
      PATHOLOGY_RESULT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-diagnosticresult-path"
      DIAGNOSTIC_RESULT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-diagnosticresult"
      AU_CORE_PATIENT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-patient"
      AU_BASE_PATIENT = "http://hl7.org.au/fhir/StructureDefinition/au-patient"

      def observation_profiles
        {
          BODY_HEIGHT => body_height,
          BODY_WEIGHT => body_weight,
          PATHOLOGY_RESULT => profile("Observation", pattern_element("Observation.category", "laboratory")),
          DIAGNOSTIC_RESULT => profile("Observation")
        }
      end

      # The code as a `patternCodeableConcept`.
      def body_height
        profile("Observation", *vital_signs_category,
                pattern_element("Observation.code", "8302-2", system: LOINC))
      end

      # The code as `fixedCode` and `fixedUri` on a coding slice.
      def body_weight
        profile("Observation", *vital_signs_category,
                *coding_slice("Observation.code.coding:BodyWeightCode", LOINC, "29463-7"))
      end

      def vital_signs_category
        coding_slice("Observation.category:VSCat.coding", OBSERVATION_CATEGORY, "vital-signs")
      end

      def coding_slice(id, system, code)
        path = id.gsub(/:[^.]+/, "")
        [{ "id" => "#{id}.system", "path" => "#{path}.system", "fixedUri" => system },
         { "id" => "#{id}.code", "path" => "#{path}.code", "fixedCode" => code }]
      end

      def pattern_element(path, code, system: OBSERVATION_CATEGORY)
        { "id" => path, "path" => path,
          "patternCodeableConcept" => { "coding" => [{ "system" => system, "code" => code }] } }
      end

      def profile(type, *elements)
        { "type" => type, "elements" => [{ "id" => type, "path" => type }, *elements] }
      end

      def matcher_for(profiles)
        ProfileMatcher.new(*suite_for(profiles))
      end

      # The groups and `IGResources` of a suite with these profiles.
      def suite_for(profiles)
        ig_resources = Generator::IGResources.new
        groups = profiles.map do |url, definition|
          ig_resources.add(structure_definition(url, definition))
          Generator::GroupMetadata.new(resource: definition["type"], profile_url: url)
        end
        [groups, ig_resources]
      end

      def structure_definition(url, definition)
        FHIR::StructureDefinition.new(
          "resourceType" => "StructureDefinition", "url" => url, "type" => definition["type"],
          "kind" => "resource", "derivation" => "constraint",
          "snapshot" => { "element" => definition["elements"] }
        )
      end

      def match_urls(matcher, query)
        input = ProfileMatcher.from_query(query)
        result = matcher.match(input[:resource_type], codes: input[:codes])
        result && { groups: result[:groups].map(&:profile_url), matched_by: result[:matched_by] }
      end
    end

    # Verifies `ProfileMatcher` builds its input from queries.
    class ProfileMatcherInputTest < Minitest::Test
      include ProfileMatcherFixtures

      def test_from_query_reads_codes_with_and_without_system
        input = ProfileMatcher.from_query("Observation?code=#{LOINC}|8302-2,8306-3&_sort=-date&category=vital-signs")

        assert_equal "Observation", input[:resource_type]
        assert_equal({ code: [{ system: LOINC, code: "8302-2" }, { system: nil, code: "8306-3" }],
                       category: [{ system: nil, code: "vital-signs" }] }, input[:codes])
      end

      def test_from_query_skips_templated_values
        input = ProfileMatcher.from_query("Observation?code={{%codes}}&patient={{%patient.id}}")

        assert_equal({ code: [], category: [] }, input[:codes])
      end
    end

    # Verifies `ProfileMatcher` picks the groups a source links to, from the
    # resource type and the `code` and `category` values the profiles fix.
    class ProfileMatcherTest < Minitest::Test
      include ProfileMatcherFixtures

      def test_one_group_matches_by_resource_type
        matcher = matcher_for(BODY_HEIGHT => body_height)

        assert_equal({ groups: [BODY_HEIGHT], matched_by: "resource_type" },
                     match_urls(matcher, "Observation?code=8302-2"))
      end

      def test_the_profile_with_the_queried_code_wins
        matcher = matcher_for(observation_profiles)

        assert_equal({ groups: [BODY_HEIGHT], matched_by: "code" }, match_urls(matcher, "Observation?code=8302-2"))
        assert_equal({ groups: [BODY_WEIGHT], matched_by: "code" },
                     match_urls(matcher, "Observation?code=#{LOINC}|29463-7"))
      end

      def test_profile_codes_reads_fixed_code_slices_with_their_system
        matcher = matcher_for(BODY_WEIGHT => body_weight)
        group = Generator::GroupMetadata.new(resource: "Observation", profile_url: BODY_WEIGHT)

        assert_equal({ code: [{ system: LOINC, code: "29463-7" }],
                       category: [{ system: OBSERVATION_CATEGORY, code: "vital-signs" }] },
                     matcher.profile_codes(group))
      end

      def test_a_category_query_matches_every_profile_with_that_category
        matcher = matcher_for(observation_profiles)

        assert_output(/matches several profiles/) do
          assert_equal({ groups: [BODY_HEIGHT, BODY_WEIGHT], matched_by: "code" },
                       match_urls(matcher, "Observation?category=vital-signs"))
        end
      end

      def test_a_code_that_no_profile_has_is_unresolved
        matcher = matcher_for(observation_profiles)

        assert_output(/unresolved Observation: no Observation profile matches code=1234-5/) do
          assert_nil match_urls(matcher, "Observation?code=1234-5")
        end
      end

      def test_a_code_with_another_system_is_unresolved
        matcher = matcher_for(observation_profiles)

        assert_output(/unresolved/) { assert_nil match_urls(matcher, "Observation?code=http://snomed.info/sct|8302-2") }
      end

      def test_a_type_without_a_group_is_untraced
        matcher = matcher_for(BODY_HEIGHT => body_height)

        assert_output(/untraced GP CCMP ObsBloodPressure: no group for Condition/) do
          assert_nil matcher.match("Condition", context: "GP CCMP ObsBloodPressure")
        end
      end

      def test_any_of_type_matches_every_group_of_the_type
        matcher = matcher_for(AU_CORE_PATIENT => profile("Patient"), AU_BASE_PATIENT => profile("Patient"))
        result = matcher.match("Patient", any_of_type: true)

        assert_equal [AU_CORE_PATIENT, AU_BASE_PATIENT], result[:groups].map(&:profile_url)
        assert_equal "resource_type", result[:matched_by]
      end

      def test_a_template_matches_by_its_code_coding
        matcher = matcher_for(observation_profiles)
        template = {
          "resourceType" => "Observation",
          "id" => "BodyHeightTemplate",
          "code" => { "coding" => [{ "system" => LOINC, "code" => "8302-2" },
                                   { "system" => "http://snomed.info/sct", "code" => "50373000" }] }
        }
        input = ProfileMatcher.from_template(template)

        result = matcher.match(input[:resource_type], codes: input[:codes])

        assert_equal [BODY_HEIGHT], result[:groups].map(&:profile_url)
      end
    end

    # Questionnaire builders shared by the `Tracer` tests. The suite has the
    # `ProfileMatcherFixtures` Observation profiles.
    module TracerFixtures
      include ProfileMatcherFixtures

      FORM_URL = "http://www.health.gov.au/assessments/GPChronicConditionManagementPlan"
      HEIGHT_QUERY = "Observation?code=8302-2&_sort=-date&patient={{%patient.id}}"
      WEIGHT_QUERY = "Observation?code=29463-7&_sort=-date&patient={{%patient.id}}"

      def trace(form, profiles: observation_profiles, resources: [])
        groups, ig_resources = suite_for(profiles)
        [FHIR::Questionnaire.new(form), *resources].each { |resource| ig_resources.add(resource) }
        Tracer.new(ig_resources, groups).trace
      end

      def questionnaire(extension: [], item: [])
        { "resourceType" => "Questionnaire", "url" => FORM_URL, "version" => "0.1.0",
          "title" => "GP Chronic Condition Management Plan", "status" => "draft",
          "extension" => extension, "item" => item }
      end

      def item(link_id, text, *extensions, children: [])
        { "linkId" => link_id, "text" => text, "type" => children.empty? ? "decimal" : "group",
          "extension" => extensions, "item" => children }
      end

      def query_variable(name, query)
        { "url" => "http://hl7.org/fhir/StructureDefinition/variable",
          "valueExpression" => { "name" => name, "language" => "application/x-fhir-query", "expression" => query } }
      end

      def expression(name, fhirpath)
        { "url" => "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-#{name}",
          "valueExpression" => { "language" => "text/fhirpath", "expression" => fhirpath } }
      end

      def fhirpath_variable(name, fhirpath)
        { "url" => "http://hl7.org/fhir/StructureDefinition/variable",
          "valueExpression" => { "name" => name, "language" => "text/fhirpath", "expression" => fhirpath } }
      end
    end

    # Verifies `Tracer` finds the x-fhir-query variables that link a
    # questionnaire to a profile, and the items that use them.
    class TracerQueryTest < Minitest::Test
      include TracerFixtures

      def test_a_root_variable_used_by_an_item
        form = questionnaire(
          extension: [query_variable("ObsBodyHeight", HEIGHT_QUERY)],
          item: [item("height", "Height",
                      expression("initialExpression", "%ObsBodyHeight.entry.resource.first().value.value"))]
        )

        assert_equal({ BODY_HEIGHT => [height_entry] }, trace(form))
      end

      def test_an_item_variable_is_used_only_within_that_item
        entry = trace(weight_in_a_group_form)[BODY_WEIGHT].first

        assert_equal "vitals", entry[:defined_at]
        assert_equal(["weight"], entry[:used_in].map { |usage| usage[:link_id] })
        assert_equal ["value"], entry[:elements_read]
      end

      def test_a_variable_that_no_item_uses_still_gets_an_entry
        form = questionnaire(extension: [query_variable("ObsBodyHeight", HEIGHT_QUERY)],
                             item: [item("height", "Height")])
        entry = trace(form)[BODY_HEIGHT].first

        assert_empty entry[:used_in]
        assert_empty entry[:elements_read]
      end

      def test_a_query_for_a_type_without_a_group_is_untraced
        form = questionnaire(extension: [query_variable("Conditions", "Condition?patient={{%patient.id}}")])

        assert_output(/untraced GP Chronic Condition Management Plan query Conditions/) { assert_empty trace(form) }
      end

      private

      def height_entry
        {
          source: "query", questionnaire_url: FORM_URL, questionnaire_version: "0.1.0",
          questionnaire_title: "GP Chronic Condition Management Plan",
          name: "ObsBodyHeight", defined_at: "root", query: HEIGHT_QUERY, matched_by: "code",
          elements_read: ["value.value"],
          used_in: [{ link_id: "height", text: "Height", extension: "initialExpression" }]
        }
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

    # Verifies `Tracer` follows variable chains: items that read a query
    # through `text/fhirpath` variables count as its users.
    class TracerAliasTest < Minitest::Test
      include TracerFixtures

      # The GP CCMP chain: `ObsBodyHeight` -> `ObsBodyHeightLatest` ->
      # `ObsBodyHeightValue`, read by the `height` item.
      def test_an_item_reads_a_query_through_a_chain_of_aliases
        entry = trace(height_chain_form)[BODY_HEIGHT].first

        assert_equal [{ link_id: "height", text: "Height", extension: "initialExpression", via: "ObsBodyHeightValue" }],
                     entry[:used_in]
        assert_equal ["value.value"], entry[:elements_read]
      end

      def test_users_of_an_alias_that_stops_at_select_add_no_path
        form = questionnaire(
          extension: [query_variable("ObsBodyHeight", HEIGHT_QUERY),
                      fhirpath_variable("HeightCodes", "%ObsBodyHeight.entry.resource.code.select(coding.code)")],
          item: [item("codes", "Codes", expression("initialExpression", "%HeightCodes.first().length()"))]
        )
        entry = trace(form)[BODY_HEIGHT].first

        assert_equal(["HeightCodes"], entry[:used_in].map { |usage| usage[:via] })
        assert_equal ["code"], entry[:elements_read]
      end

      def test_an_alias_on_an_item_is_not_visible_to_a_sibling
        entry = trace(alias_in_a_group_form)[BODY_HEIGHT].first

        assert_equal [{ link_id: "vitals", text: "Vitals", extension: "variable" },
                      { link_id: "height", text: "Height", extension: "initialExpression", via: "HeightLatest" }],
                     entry[:used_in]
        assert_equal ["value"], entry[:elements_read]
      end

      def test_aliases_that_reference_each_other_do_not_loop
        form = questionnaire(extension: [query_variable("ObsBodyHeight", HEIGHT_QUERY),
                                         fhirpath_variable("A", "%B | %ObsBodyHeight.entry.resource"),
                                         fhirpath_variable("B", "%A")],
                             item: [item("height", "Height", expression("initialExpression", "%B.value"))])

        assert_equal(["B"], trace(form)[BODY_HEIGHT].first[:used_in].map { |usage| usage[:via] })
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

    # Verifies `Tracer` traces `_include` targets as their own entries, and
    # routes each chain to the include or the query entry by its type.
    class TracerIncludeTest < Minitest::Test
      include TracerFixtures

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

        assert_equal [medication_entry], traces[MEDICATION]
      end

      def test_a_chain_without_of_type_in_the_same_item_goes_to_the_query_entry
        traces = trace(medications_form, profiles: suite_profiles, resources: [medication_param])
        entry = traces[MEDICATION_STATEMENT].first

        assert_equal "query", entry[:source]
        assert_equal(["medications"], entry[:used_in].map { |usage| usage[:link_id] })
        assert_equal ["medication"], entry[:elements_read]
      end

      def test_an_explicit_target_type
        entry = trace(location_form("PractitionerRole:location:Location"), profiles: suite_profiles)[LOCATION].first

        assert_equal "explicit", entry[:target_by]
        assert_equal ["name"], entry[:elements_read]
        assert_equal(["location"], entry[:used_in].map { |usage| usage[:link_id] })
      end

      def test_a_target_type_from_of_type_in_the_form
        entry = trace(location_form("PractitionerRole:location"), profiles: suite_profiles)[LOCATION].first

        assert_equal "of_type", entry[:target_by]
        assert_equal "PractitionerRole:location", entry[:include]
      end

      def test_an_include_without_a_search_parameter_or_of_type_is_unresolved
        query = location_query("PractitionerRole:location")
        form = questionnaire(extension: [query_variable("PractitionerRoleLocation", query)])

        assert_output(/unresolved .* include PractitionerRole:location: no target type/) do
          refute trace(form, profiles: suite_profiles).key?(LOCATION)
        end
      end

      def test_an_include_iterate_is_skipped
        query = "#{MEDS_QUERY}&_include:iterate=Medication:manufacturer"
        form = questionnaire(extension: [query_variable("MedicationStatement", query)])

        assert_output(/skipping _include:iterate=Medication:manufacturer/) do
          trace(form, profiles: suite_profiles, resources: [medication_param])
        end
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
        {
          source: "include", questionnaire_url: FORM_URL, questionnaire_version: "0.1.0",
          questionnaire_title: "GP Chronic Condition Management Plan",
          name: "MedicationStatement", defined_at: "root", query: MEDS_QUERY,
          include: "MedicationStatement:medication", target_by: "search_parameter", matched_by: "resource_type",
          elements_read: [], used_in: [{ link_id: "medications", text: "Medications", extension: "initialExpression" }]
        }
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
  end
end
