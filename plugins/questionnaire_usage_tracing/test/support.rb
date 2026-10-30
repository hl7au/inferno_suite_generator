# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "inferno_suite_generator"
require "inferno_suite_generator/plugins/testing"
require_relative "../lib/questionnaire_usage_tracing"

module InfernoSuitePlugins
  module QuestionnaireUsageTracing
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
      SNOMED = "http://snomed.info/sct"
      RECORDED_SEX_URL = "http://hl7.org/fhir/StructureDefinition/individual-recordedSexOrGender"

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
        ig_resources = InfernoSuiteGenerator::Generator::IGResources.new
        groups = profiles.map do |url, definition|
          ig_resources.add(structure_definition(url, definition))
          InfernoSuiteGenerator::Generator::GroupMetadata.new(resource: definition["type"], profile_url: url)
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

    # Questionnaire builders shared by the `Tracer` tests. The suite has the
    # `ProfileMatcherFixtures` Observation profiles.
    module TracerFixtures
      include ProfileMatcherFixtures

      FORM_URL = "http://www.health.gov.au/assessments/GPChronicConditionManagementPlan"
      FORM_TITLE = "GP Chronic Condition Management Plan"
      HEIGHT_QUERY = "Observation?code=8302-2&_sort=-date&patient={{%patient.id}}"
      WEIGHT_QUERY = "Observation?code=29463-7&_sort=-date&patient={{%patient.id}}"

      def trace(form, profiles: observation_profiles, resources: [])
        groups, ig_resources = suite_for(profiles)
        [FHIR::Questionnaire.new(form), *resources].each { |resource| ig_resources.add(resource) }
        Tracer.new(ig_resources, groups).trace
      end

      def questionnaire(extension: [], item: [], contained: [])
        { "resourceType" => "Questionnaire", "url" => FORM_URL, "version" => "0.1.0",
          "title" => FORM_TITLE, "status" => "draft",
          "contained" => contained, "extension" => extension, "item" => item }
      end

      def item(link_id, text, *extensions, children: [])
        { "linkId" => link_id, "text" => text, "type" => children.empty? ? "decimal" : "group",
          "extension" => extensions, "item" => children }
      end

      # The questionnaire fields every trace entry starts with.
      def form_header
        { questionnaire_url: FORM_URL, questionnaire_version: "0.1.0", questionnaire_title: FORM_TITLE }
      end

      def link_ids(entry)
        entry[:used_in].map { |usage| usage[:link_id] }
      end

      def vias(entry)
        entry[:used_in].map { |usage| usage[:via] }
      end

      def query_variable(name, query)
        { "url" => "http://hl7.org/fhir/StructureDefinition/variable",
          "valueExpression" => { "name" => name, "language" => "application/x-fhir-query", "expression" => query } }
      end

      def expression(name, fhirpath)
        { "url" => "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-#{name}",
          "valueExpression" => { "language" => "text/fhirpath", "expression" => fhirpath } }
      end

      # `value_id: true` gives the name as `valueId`, like older SDC versions.
      def launch_context(name, *types, value_id: false)
        name_part = value_id ? { "valueId" => name } : { "valueCoding" => { "code" => name } }
        { "url" => "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-launchContext",
          "extension" => [{ "url" => "name", **name_part },
                          *types.map { |type| { "url" => "type", "valueCode" => type } }] }
      end

      def assemble_context(name)
        { "url" => "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-assembleContext",
          "valueString" => name }
      end

      def fhirpath_variable(name, fhirpath)
        { "url" => "http://hl7.org/fhir/StructureDefinition/variable",
          "valueExpression" => { "name" => name, "language" => "text/fhirpath", "expression" => fhirpath } }
      end
    end

    # Entries and a Patient group shared by the `UsageSection`,
    # `ElementReads` and `GroupSummary` tests.
    module UsageSectionFixtures
      include TracerFixtures

      INDIGENOUS_STATUS = "http://hl7.org.au/fhir/StructureDefinition/indigenous-status"
      PRONOUNS = "http://hl7.org/fhir/StructureDefinition/individual-pronouns"
      LOCATION_QUERY = "PractitionerRole?_id={{%role.id}}&_include=PractitionerRole:location"

      # The list as the group summary shows it, with the search check.
      def section(entries, group: patient_group, search_check: true)
        list = UsageSection.new(entries, group, search_check:).list
        list.empty? ? "" : "#{list}\n"
      end

      def launch_entry(reads: ["birthDate"],
                       used_in: [{ link_id: "dob", text: "Date of birth", extension: "initialExpression", reads: }])
        { source: "launch_context", **form_header, name: "patient", used_in: }
      end

      def variable_usage
        { link_id: "group", text: "Group", extension: "variable", reads: ["name"] }
      end

      def query_entry(query, used_in: [{ link_id: "name", text: "Name", extension: "initialExpression" }])
        { source: "query", **form_header, name: "Patients", query:, used_in: }
      end

      def template_entry(patch:, template_codes: [],
                         used_in: [{ link_id: "height", text: "Height", extension: "templateExtract" }])
        { source: "template_extract", **form_header, name: "height", patch:, template_codes:, used_in: }
      end

      def patient_group(searches: [{ names: ["_id"] }, { names: %w[family gender] }])
        InfernoSuiteGenerator::Generator::GroupMetadata.new(
          resource: "Patient", profile_url: AU_CORE_PATIENT, searches:, mandatory_elements: ["Patient.gender"],
          must_supports: { elements: [{ path: "birthDate" }, { path: "deceasedBoolean" }],
                           slices: [{ slice_id: "Patient.deceased[x]:deceasedBoolean", path: "deceased[x]" }],
                           extensions: [{ id: "Patient.extension:indigenousStatus", url: INDIGENOUS_STATUS }] }
        )
      end
    end

    # A temporary suite directory and a Patient group whose profile marks
    # birthDate Must Support, for tests that run the plugin the way the host
    # does.
    module PluginRunFixtures
      include TracerFixtures
      include InfernoSuiteGenerator::Plugins::Testing

      PLUGIN_ROOT = File.expand_path("..", __dir__)
      PLUGIN_ID = "questionnaire_usage_tracing"

      def setup
        @dir = Dir.mktmpdir
        @group = build_group_metadata(resource: "Patient", profile_url: AU_CORE_PATIENT,
                                      must_supports: { elements: [{ path: "birthDate" }] })
      end

      def teardown
        FileUtils.remove_entry(@dir)
      end

      # Runs the plugin over the form and returns the descriptions it added.
      def run_tracing(form = patient_form, groups: [@group], profiles: { AU_CORE_PATIENT => profile("Patient") })
        _groups, ig_resources = suite_for(profiles)
        ig_resources.add(FHIR::Questionnaire.new(form))
        run_plugin(PLUGIN_ROOT, ig_metadata: build_ig_metadata(groups:), ig_resources:, base_output_dir: @dir)
      end

      def add_test(group, id, kind, **details)
        group.add_test(id:, file_name: "#{id}.rb", kind:, **details)
      end

      # Writes the Patient group file with the descriptions and returns its path.
      def generate_group_file(descriptions)
        FileUtils.mkdir_p(File.join(@dir, "patient"))
        with_config_keeper do
          InfernoSuiteGenerator::Generator::GroupGenerator.generate(build_ig_metadata(groups: [@group]), @dir,
                                                                    descriptions)
        end
        File.join(@dir, "patient_group.rb")
      end

      def patient_form(text: "Date of birth")
        questionnaire(extension: [launch_context("patient", "Patient")],
                      item: [item("dob", text, expression("initialExpression", "%patient.birthDate.toString()"))])
      end
    end
  end
end
