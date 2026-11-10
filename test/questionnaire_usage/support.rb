# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../generator_fixtures"
require "tmpdir"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Profiles for the suites the tests trace. Body Height fixes its code with a
    # `patternCodeableConcept`, Body Weight with `fixedCode` and `fixedUri` on a
    # coding slice, like the real AU Core profiles.
    module SuiteFixtures
      LOINC = "http://loinc.org"
      SNOMED = "http://snomed.info/sct"
      OBSERVATION_CATEGORY = "http://terminology.hl7.org/CodeSystem/observation-category"
      BODY_HEIGHT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-bodyheight"
      BODY_WEIGHT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-bodyweight"
      PATHOLOGY_RESULT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-diagnosticresult-path"
      DIAGNOSTIC_RESULT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-diagnosticresult"
      AU_CORE_PATIENT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-patient"
      AU_BASE_PATIENT = "http://hl7.org.au/fhir/StructureDefinition/au-patient"
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
    end

    # Questionnaire builders, and `trace`, which traces a form over a suite the
    # way `Tracer#trace` does for the generator.
    module FormFixtures
      include SuiteFixtures
      include InfernoSuiteGenerator::GeneratorFixtures

      FORM_URL = "http://www.health.gov.au/assessments/GPChronicConditionManagementPlan"
      FORM_TITLE = "GP Chronic Condition Management Plan"
      HEIGHT_QUERY = "Observation?code=8302-2&_sort=-date&patient={{%patient.id}}"
      WEIGHT_QUERY = "Observation?code=29463-7&_sort=-date&patient={{%patient.id}}"

      # `{ profile_url => [TraceEntry] }`.
      def trace(form, profiles: observation_profiles, resources: [])
        groups, ig_resources = suite_for(profiles)
        [FHIR::Questionnaire.new(form), *resources].each { |resource| ig_resources.add(resource) }
        Tracer.new(ig_resources, groups).trace.to_h
      end

      # What a section shows of an entry traced for a group of this resource type.
      def described(entry, resource)
        { heading: entry.heading(resource), request: entry.query&.to_s, item_uses: entry.item_uses }
      end

      def link_ids(entry)
        entry.item_uses.map(&:link_id)
      end

      # The element paths the entry's items read.
      def reads(entry)
        entry.item_uses.flat_map(&:reads).uniq
      end

      # The ids of the groups' tests whose descriptions got a section, in group order.
      def tests_with_sections(descriptions, groups)
        with_config_keeper do
          groups.flat_map do |group|
            group.tests.to_a.map { |test| test[:id].to_s }.select { |id| descriptions.for_test(group, id).any? }
          end
        end
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

      # The questionnaire of every trace entry the write tests build.
      def form_header
        FormHeader.new(url: FORM_URL, version: "0.1.0", title: FORM_TITLE)
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

    # Trace entries and groups, and `write`, which writes them the way
    # `QuestionnaireUsage.write` does for the generator.
    module WriteFixtures
      include FormFixtures

      INDIGENOUS_STATUS = "http://hl7.org.au/fhir/StructureDefinition/indigenous-status"
      PRONOUNS = "http://hl7.org/fhir/StructureDefinition/individual-pronouns"
      LOCATION_QUERY = "PractitionerRole?_id={{%role.id}}&_include=PractitionerRole:location"

      # What `QuestionnaireUsage.write` wrote: the descriptions, and the ids of
      # the tests that got a section, in group order.
      Written = Data.define(:descriptions, :tested_by)

      def write(trace, groups)
        descriptions = InfernoSuiteGenerator::Generator::GroupDescriptions.new
        with_config_keeper { QuestionnaireUsage.write(trace, groups:, descriptions:) }
        Written.new(descriptions:, tested_by: tests_with_sections(descriptions, groups))
      end

      # A Trace of the entries, each shared by all the groups.
      def trace_of(entries, groups)
        entries.each_with_object(Trace.new) { |entry, trace| trace.add(groups, entry) }
      end

      # What is written for entries traced for the group alone.
      def written(entries, group)
        write(trace_of(entries, [group]), [group])
      end

      # The group's summary for the entries, "" when it has none. A group with no
      # tests lists every source in full under "Not tested by this group".
      def summary(entries, group: patient_group)
        written(entries, group).descriptions.for(group).join
      end

      # The section written to a test of this kind, "" when it has none.
      def section_of_test(entries, kind, group: patient_group, **details)
        add_test(group, "patient_#{kind}", kind, **details)
        written(entries, group).descriptions.for_test(group, "patient_#{kind}").join
      end

      # The ids of the tests that list the entry.
      def tested_by(entry, group: patient_group)
        written([entry], group).tested_by
      end

      def add_test(group, id, kind, **details)
        group.add_test(id:, file_name: "#{id}.rb", kind:, **details)
      end

      def launch_entry(reads: ["birthDate"], header: form_header,
                       item_uses: [ItemUse.new(link_id: "dob", text: "Date of birth", extension: "initialExpression",
                                               reads:)])
        TraceEntry::LaunchContext.new(form: header, name: "patient", item_uses:)
      end

      def name_use
        ItemUse.new(link_id: "name", text: "Name", extension: "initialExpression")
      end

      def query_entry(query, item_uses: [name_use], **fields)
        TraceEntry::Query.new(form: form_header, name: "Patients", query: FhirQuery.new(query), item_uses:, **fields)
      end

      def include_entry(query, item_uses: [name_use], include: "PractitionerRole:location")
        TraceEntry::Include.new(form: form_header, name: "Roles", query: FhirQuery.new(query), item_uses:, include:)
      end

      def template_entry(patch:, template_codes: [],
                         item_uses: [ItemUse.new(link_id: "height", text: "Height", extension: "templateExtract")])
        TraceEntry::Template.new(form: form_header, name: "height", patch:, template_codes:, item_uses:)
      end

      # A Patient group whose profile marks birthDate, deceasedBoolean and the
      # Indigenous Status extension Must Support and requires gender.
      def patient_group(searches: [{ names: ["_id"] }, { names: %w[family gender] }])
        InfernoSuiteGenerator::Generator::GroupMetadata.new(
          resource: "Patient", profile_url: AU_CORE_PATIENT, searches:, mandatory_elements: ["Patient.gender"],
          must_supports: { elements: [{ path: "birthDate" }, { path: "deceasedBoolean" }],
                           slices: [{ slice_id: "Patient.deceased[x]:deceasedBoolean", path: "deceased[x]" }],
                           extensions: [{ id: "Patient.extension:indigenousStatus", url: INDIGENOUS_STATUS }] }
        )
      end
    end

    # A temporary suite directory for the group files and a Patient group whose
    # profile marks birthDate Must Support, for tests that run the tracing the
    # way the generator does.
    module RunFixtures
      include FormFixtures

      def setup
        @dir = Dir.mktmpdir
        @group = build_group_metadata(resource: "Patient", profile_url: AU_CORE_PATIENT,
                                      must_supports: { elements: [{ path: "birthDate" }] })
        add_test(@group, "patient_validation_test", "validation")
      end

      def teardown
        FileUtils.remove_entry(@dir)
      end

      # Runs the tracing over the form and returns the descriptions it added.
      def run_tracing(form = patient_form, groups: [@group], profiles: { AU_CORE_PATIENT => profile("Patient") })
        _groups, ig_resources = suite_for(profiles)
        ig_resources.add(FHIR::Questionnaire.new(form))
        InfernoSuiteGenerator::Generator::GroupDescriptions.new.tap do |descriptions|
          with_config_keeper do
            QuestionnaireUsage.generate(ig_resources:, groups:, descriptions:)
          end
        end
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
