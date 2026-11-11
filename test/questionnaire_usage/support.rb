# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../generator_fixtures"
require "tmpdir"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Profiles and groups for the suites the tests trace, and `Written`, what tracing wrote for them.
    module SuiteFixtures
      include InfernoSuiteGenerator::GeneratorFixtures

      LOINC = "http://loinc.org"
      SNOMED = "http://snomed.info/sct"
      OBSERVATION_CATEGORY = "http://terminology.hl7.org/CodeSystem/observation-category"
      BODY_HEIGHT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-bodyheight"
      BODY_WEIGHT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-bodyweight"
      PATHOLOGY_RESULT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-diagnosticresult-path"
      DIAGNOSTIC_RESULT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-diagnosticresult"
      AU_CORE_PATIENT = "http://hl7.org.au/fhir/core/StructureDefinition/au-core-patient"
      AU_BASE_PATIENT = "http://hl7.org.au/fhir/StructureDefinition/au-patient"
      ROLE = "http://example.org/StructureDefinition/role"
      LOCATION = "http://example.org/StructureDefinition/location"
      UNCHECKING = "http://example.org/StructureDefinition/obs-unchecking"
      CHECKING = "http://example.org/StructureDefinition/obs-checking"

      # What tracing wrote: each group's summary, and the section of each test that got one by its id, in group
      # order. A group or test without one has "".
      Written = Data.define(:summaries, :sections) do
        def summary(group) = summaries.fetch(group)
        def section(test_id) = sections[test_id].to_s
        def tested_by = sections.keys
      end

      def observation_profiles
        {
          BODY_HEIGHT => body_height,
          BODY_WEIGHT => body_weight,
          PATHOLOGY_RESULT => profile("Observation", pattern_element("Observation.category", "laboratory")),
          DIAGNOSTIC_RESULT => profile("Observation")
        }
      end

      def role_profiles
        { ROLE => profile("PractitionerRole"), LOCATION => profile("Location") }
      end

      def patient_profile
        { AU_CORE_PATIENT => profile("Patient") }
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

      # What the descriptions hold for the groups. Call it under the config, which names groups that share a type.
      def written_in(descriptions, groups)
        Written.new(summaries: groups.to_h { |group| [group, descriptions.for(group).join] }.compare_by_identity,
                    sections: groups.flat_map { |group| sections_in(descriptions, group) }.to_h)
      end

      # `[test id, section]` for each of the group's tests that got one.
      def sections_in(descriptions, group)
        ids = group.tests.to_a.map { |test| test[:id].to_s }
        ids.map { |id| [id, descriptions.for_test(group, id).join] }.reject { |_id, section| section.empty? }
      end

      # Adds tests of these kinds to the group and returns it. A kind has one details Hash, or a list of them for
      # several tests. Their ids are `<prefix>_<kind>`, numbered when the kind has a list.
      def with_tests(group, prefix, **tests)
        tests.each do |kind, details|
          Array.wrap(details).each.with_index(1) do |test_details, index|
            id = [prefix, kind, (index if details.is_a?(Array))].compact.join("_")
            add_test(group, id, kind.to_s, **test_details)
          end
        end
        group
      end

      def add_test(group, id, kind, **details)
        group.add_test(id:, file_name: "#{id}.rb", kind:, **details)
      end

      # An Observation group with a `<name>_must_support` test.
      def observation_group(name, profile_url, **must_supports)
        with_tests(build_group_metadata(name: "obs_#{name}", resource: "Observation", profile_url:, must_supports:),
                   name, must_support: {})
      end
    end

    # Questionnaire builders, and `trace`, which traces a form over a suite the way `Tracer#trace` does for the
    # generator.
    module FormFixtures
      include SuiteFixtures

      RECORDED_SEX_URL = "http://hl7.org/fhir/StructureDefinition/individual-recordedSexOrGender"
      SDC = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-"
      PATCH_URL = "https://smartforms.csiro.au/ig/StructureDefinition/TemplateExtractExtensionPatchRequestUrl"
      FORM_URL = "http://www.health.gov.au/assessments/GPChronicConditionManagementPlan"
      FORM_TITLE = "GP Chronic Condition Management Plan"
      HEIGHT_QUERY = "Observation?code=8302-2&_sort=-date&patient={{%patient.id}}"
      WEIGHT_QUERY = "Observation?code=29463-7&_sort=-date&patient={{%patient.id}}"
      LOCATION_NAME = "%PractitionerRoleLocation.entry.resource.ofType(Location).first().name"

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

      def questionnaire(extension: [], item: [], contained: [])
        { "resourceType" => "Questionnaire", "url" => FORM_URL, "version" => "0.1.0",
          "title" => FORM_TITLE, "status" => "draft",
          "contained" => contained, "extension" => extension, "item" => item }
      end

      def item(link_id, text, *extensions, children: [])
        { "linkId" => link_id, "text" => text, "type" => children.empty? ? "decimal" : "group",
          "extension" => extensions, "item" => children }
      end

      # A form whose `location` item reads `fhirpath` from a PractitionerRole search that includes its Locations.
      def location_form(include: "PractitionerRole:location:Location", fhirpath: LOCATION_NAME, variables: [])
        questionnaire(extension: [query_variable("PractitionerRoleLocation", role_query(include)), *variables],
                      item: [item("location", "Location", expression("initialExpression", fhirpath))])
      end

      def role_query(include = "PractitionerRole:location:Location")
        "PractitionerRole?practitioner={{%user.id}}&_include=#{include}"
      end

      def query_variable(name, query)
        variable(name, query, "application/x-fhir-query")
      end

      def fhirpath_variable(name, fhirpath)
        variable(name, fhirpath, "text/fhirpath")
      end

      def variable(name, expression, language)
        { "url" => "http://hl7.org/fhir/StructureDefinition/variable",
          "valueExpression" => { "name" => name, "language" => language, "expression" => expression } }
      end

      def expression(name, fhirpath)
        { "url" => "#{SDC}#{name}", "valueExpression" => { "language" => "text/fhirpath", "expression" => fhirpath } }
      end

      # `value_id: true` gives the name as `valueId`, like older SDC versions.
      def launch_context(name, *types, value_id: false)
        name_part = value_id ? { "valueId" => name } : { "valueCoding" => { "code" => name } }
        { "url" => "#{SDC}launchContext",
          "extension" => [{ "url" => "name", **name_part },
                          *types.map { |type| { "url" => "type", "valueCode" => type } }] }
      end

      def assemble_context(name)
        { "url" => "#{SDC}assembleContext", "valueString" => name }
      end

      # A `templateExtract` of a contained resource; `patch_url:` adds the smartforms PATCH request URL.
      def template_extract(reference, patch_url: nil)
        parts = [{ "url" => "template", "valueReference" => { "reference" => reference } }]
        parts << { "url" => PATCH_URL, "valueString" => patch_url } if patch_url
        { "url" => "#{SDC}templateExtract", "extension" => parts }
      end

      # A FHIRPath Patch `Parameters`, with one `add` operation on `path` when given.
      def patch_template(id, path: nil)
        parts = [{ "name" => "type", "valueCode" => "add" }, { "name" => "name", "valueString" => "clinicalStatus" }]
        parts << { "name" => "path", "valueString" => path } if path
        { "resourceType" => "Parameters", "id" => id, "parameter" => [{ "name" => "operation", "part" => parts }] }
      end
    end

    # Trace entries and groups, and `write`, which writes them the way
    # `QuestionnaireUsage.write` does for the generator.
    module WriteFixtures
      include FormFixtures

      INDIGENOUS_STATUS = "http://hl7.org.au/fhir/StructureDefinition/indigenous-status"
      PRONOUNS = "http://hl7.org/fhir/StructureDefinition/individual-pronouns"
      LOCATION_QUERY = "PractitionerRole?_id={{%role.id}}&_include=PractitionerRole:location"

      # What `QuestionnaireUsage.write` wrote for the groups.
      def write(trace, groups)
        descriptions = InfernoSuiteGenerator::Generator::GroupDescriptions.new
        with_config_keeper do
          QuestionnaireUsage.write(trace, groups:, descriptions:)
          written_in(descriptions, groups)
        end
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
        written(entries, group).summary(group)
      end

      # The section written to a test of this kind, "" when it has none.
      def section_of_test(entries, kind, group: patient_group, **details)
        add_test(group, "patient_#{kind}", kind, **details)
        written(entries, group).section("patient_#{kind}")
      end

      # The ids of the tests that list the entry.
      def tested_by(entry, group: patient_group)
        written([entry], group).tested_by
      end

      # The questionnaire of every trace entry the write tests build.
      def form_header
        FormHeader.new(url: FORM_URL, version: "0.1.0", title: FORM_TITLE)
      end

      def launch_entry(reads: ["birthDate"], header: form_header,
                       item_uses: [ItemUse.new(link_id: "dob", text: "Date of birth", extension: "initialExpression",
                                               reads:)])
        TraceEntry::LaunchContext.new(header:, name: "patient", item_uses:)
      end

      def name_use
        ItemUse.new(link_id: "name", text: "Name", extension: "initialExpression")
      end

      def query_entry(query, item_uses: [name_use], **fields)
        TraceEntry::Query.new(header: form_header, name: "Patients", query: FhirQuery.new(query), item_uses:, **fields)
      end

      def include_entry(query, item_uses: [name_use], include: "PractitionerRole:location")
        TraceEntry::Include.new(header: form_header, name: "Roles", query: FhirQuery.new(query), item_uses:, include:)
      end

      def template_entry(patch:, template_codes: [],
                         item_uses: [ItemUse.new(link_id: "height", text: "Height", extension: "templateExtract")])
        TraceEntry::Template.new(header: form_header, name: "height", patch:, template_codes:, item_uses:)
      end

      # A Patient group whose profile marks birthDate, deceasedBoolean and the Indigenous Status extension Must
      # Support and requires gender, with `patient_<kind>` tests of the kinds in `tests`.
      def patient_group(searches: [{ names: ["_id"] }, { names: %w[family gender] }], tests: {})
        group = InfernoSuiteGenerator::Generator::GroupMetadata.new(
          resource: "Patient", profile_url: AU_CORE_PATIENT, searches:, mandatory_elements: ["Patient.gender"],
          must_supports: { elements: [{ path: "birthDate" }, { path: "deceasedBoolean" }],
                           slices: [{ slice_id: "Patient.deceased[x]:deceasedBoolean", path: "deceased[x]" }],
                           extensions: [{ id: "Patient.extension:indigenousStatus", url: INDIGENOUS_STATUS }] }
        )
        with_tests(group, "patient", **tests)
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

      # What `QuestionnaireUsage.generate` wrote for the groups when it traced the form.
      def run_tracing(form = patient_form, groups: [@group], profiles: patient_profile)
        with_config_keeper { written_in(descriptions_of(form, groups, profiles), groups) }
      end

      def descriptions_of(form, groups, profiles)
        _groups, ig_resources = suite_for(profiles)
        ig_resources.add(FHIR::Questionnaire.new(form))
        InfernoSuiteGenerator::Generator::GroupDescriptions.new.tap do |descriptions|
          QuestionnaireUsage.generate(ig_resources:, groups:, descriptions:)
        end
      end

      # Traces the form, writes the Patient group file with what that added, and returns its path.
      def generate_group_file(form)
        FileUtils.mkdir_p(File.join(@dir, "patient"))
        with_config_keeper do
          descriptions = descriptions_of(form, [@group], patient_profile)
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
