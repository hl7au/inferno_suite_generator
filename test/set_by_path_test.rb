# frozen_string_literal: true

require_relative "test_helper"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  class SetByPathTest < Minitest::Test
    def test_set_top_level_string
      resource = { "resourceType" => "Patient", "id" => "123" }
      result = SetByPath.set_by_path(resource, "resourceType", "Observation")
      assert_equal "Observation", result["resourceType"]
      assert_equal "123", result["id"]
      assert_equal "Patient", resource["resourceType"], "original hash unchanged"
    end

    def test_set_top_level_new_key
      resource = { "resourceType" => "Patient" }
      result = SetByPath.set_by_path(resource, "status", "active")
      assert_equal "active", result["status"]
      refute resource.key?("status"), "original hash unchanged"
    end

    def test_set_nested_direct
      resource = { "resourceType" => "Patient", "meta" => { "profile" => ["http://a"] } }
      result = SetByPath.set_by_path(resource, "meta.versionId", "v2")
      assert_equal "v2", result["meta"]["versionId"]
      assert_equal ["http://a"], result["meta"]["profile"]
      refute resource["meta"].key?("versionId"), "original unchanged"
    end

    def test_set_array_index
      resource = { "resourceType" => "Patient", "name" => [{ "family" => "Smith", "given" => ["John"] }] }
      result = SetByPath.set_by_path(resource, "name[0].family", "Jones")
      assert_equal "Jones", result["name"][0]["family"]
      assert_equal ["John"], result["name"][0]["given"]
      assert_equal "Smith", resource["name"][0]["family"], "original unchanged"
    end

    def test_set_creates_array_and_index
      resource = { "resourceType" => "Patient" }
      result = SetByPath.set_by_path(resource, "name[0].family", "Doe")
      assert_equal [{ "family" => "Doe" }], result["name"]
      assert_nil resource["name"], "original unchanged"
    end

    def test_set_creates_nested_hashes
      resource = { "resourceType" => "Patient" }
      result = SetByPath.set_by_path(resource, "meta.profile[0]", "http://example.org/StructureDefinition/MyPatient")
      assert_equal({ "profile" => ["http://example.org/StructureDefinition/MyPatient"] }, result["meta"])
    end

    def test_set_with_resource_type_prefix_stripped
      resource = { "resourceType" => "Patient", "name" => [{ "family" => "X" }] }
      result = SetByPath.set_by_path(resource, "Patient.name[0].family", "Y")
      assert_equal "Y", result["name"][0]["family"]
    end

    def test_set_complex_nested
      resource = {
        "resourceType" => "Patient",
        "identifier" => [
          { "system" => "http://a", "value" => "1" },
          { "system" => "http://b", "value" => "2" }
        ]
      }
      result = SetByPath.set_by_path(resource, "identifier[1].value", "two")
      assert_equal "1", result["identifier"][0]["value"]
      assert_equal "two", result["identifier"][1]["value"]
      assert_equal "2", resource["identifier"][1]["value"], "original unchanged"
    end

    def test_set_value_can_be_any_type
      resource = { "resourceType" => "Patient" }
      result = SetByPath.set_by_path(resource, "active", true)
      assert_equal true, result["active"]

      result = SetByPath.set_by_path(resource, "deceasedBoolean", false)
      assert_equal false, result["deceasedBoolean"]

      result = SetByPath.set_by_path(resource, "birthDate", "1990-01-15")
      assert_equal "1990-01-15", result["birthDate"]

      result = SetByPath.set_by_path(resource, "meta.profile", %w[url1 url2])
      assert_equal %w[url1 url2], result["meta"]["profile"]

      result = SetByPath.set_by_path(resource, "contained[0]", { "resourceType" => "Organization", "id" => "org1" })
      assert_equal({ "resourceType" => "Organization", "id" => "org1" }, result["contained"][0])
    end

    def test_set_extends_array_when_index_out_of_bounds
      resource = { "resourceType" => "Patient", "name" => [{ "family" => "A" }] }
      result = SetByPath.set_by_path(resource, "name[2].family", "C")
      assert_equal 3, result["name"].length
      assert_equal "A", result["name"][0]["family"]
      # Padded element at [1] is {} so we can navigate to [2]
      assert_equal "C", result["name"][2]["family"]
    end

    def test_returns_copy_not_same_object
      resource = { "resourceType" => "Patient", "meta" => { "profile" => [] } }
      result = SetByPath.set_by_path(resource, "id", "1")
      refute_same result, resource
      refute_same result["meta"], resource["meta"], "nested modified structure is a copy"
    end

    def test_nil_path_raises
      resource = { "resourceType" => "Patient" }
      assert_raises(ArgumentError) { SetByPath.set_by_path(resource, nil, "x") }
    end

    def test_empty_path_raises
      resource = { "resourceType" => "Patient" }
      assert_raises(ArgumentError) { SetByPath.set_by_path(resource, "", "x") }
      assert_raises(ArgumentError) { SetByPath.set_by_path(resource, "   ", "x") }
    end

    def test_nil_hash_returns_nil
      assert_nil SetByPath.set_by_path(nil, "resourceType", "Patient")
    end

    def test_supports_choice_type_x_segments
      resource = { "resourceType" => "Condition", "note" => {} }
      result = SetByPath.set_by_path(resource, "Condition.note.author[x]", { "reference" => "Practitioner/1" })
      assert_equal({ "reference" => "Practitioner/1" }, result["note"]["author[x]"])
      resource2 = { "resourceType" => "Encounter" }
      result2 = SetByPath.set_by_path(resource2, "Encounter.hospitalization.origin", { "reference" => "Location/1" })
      assert_equal({ "reference" => "Location/1" }, result2["hospitalization"]["origin"])
    end

    def test_invalid_path_segment_raises
      resource = { "resourceType" => "Patient" }
      assert_raises(ArgumentError) { SetByPath.set_by_path(resource, "name[0].family[]", "x") }
      assert_raises(ArgumentError) { SetByPath.set_by_path(resource, "name[abc].family", "x") }
    end

    def test_fhir_like_resource_full_path
      resource = {
        "resourceType" => "Observation",
        "status" => "final",
        "code" => { "coding" => [{ "system" => "http://loinc.org", "code" => "15074-8" }] },
        "subject" => { "reference" => "Patient/123" }
      }
      result = SetByPath.set_by_path(resource, "subject.reference", "Patient/456")
      assert_equal "Patient/456", result["subject"]["reference"]
      result = SetByPath.set_by_path(result, "code.coding[0].display", "Glucose")
      assert_equal "Glucose", result["code"]["coding"][0]["display"]
    end

    # --- AllergyIntolerance resource tests (SHC profile metadata) ---

    def allergy_intolerance_resource
      {
        "clinicalStatus" => {
          "coding" => [
            {
              "code" => "active",
              "system" => "http://terminology.hl7.org/CodeSystem/allergyintolerance-clinical"
            }
          ]
        },
        "code" => {
          "coding" => [
            {
              "code" => "412583005",
              "display" => "Bee pollen",
              "system" => "http://snomed.info/sct"
            }
          ],
          "text" => "Bee pollen"
        },
        "meta" => {
          "profile" => [
            "https://smartforms.csiro.au/ig/StructureDefinition/SHCAllergyIntolerance"
          ]
        },
        "note" => [
          { "text" => "comment" }
        ],
        "patient" => {
          "reference" => "Patient/pat-sf"
        },
        "reaction" => [
          {
            "manifestation" => [
              {
                "coding" => [
                  {
                    "code" => "271807003",
                    "display" => "Rash",
                    "system" => "http://snomed.info/sct"
                  }
                ],
                "text" => "Rash"
              }
            ]
          }
        ],
        "resourceType" => "AllergyIntolerance"
      }
    end

    def test_allergy_intolerance_set_resource_type_and_id
      resource = allergy_intolerance_resource
      result = SetByPath.set_by_path(resource, "resourceType", "AllergyIntolerance")
      assert_equal "AllergyIntolerance", result["resourceType"]

      result = SetByPath.set_by_path(resource, "id", "all-1")
      assert_equal "all-1", result["id"]
      refute resource.key?("id"), "original unchanged"
    end

    def test_allergy_intolerance_set_clinical_status_and_verification
      resource = allergy_intolerance_resource
      result = SetByPath.set_by_path(resource, "clinicalStatus",
                                     { "coding" => [{ "code" => "inactive", "system" => "http://terminology.hl7.org/CodeSystem/allergyintolerance-clinical" }] })
      assert_equal "inactive", result["clinicalStatus"]["coding"][0]["code"]

      result = SetByPath.set_by_path(resource, "verificationStatus",
                                     { "coding" => [{ "code" => "confirmed", "system" => "http://hl7.org/fhir/ValueSet/allergyintolerance-verification" }] })
      assert_equal "confirmed", result["verificationStatus"]["coding"][0]["code"]
    end

    def test_allergy_intolerance_set_code_and_code_text
      resource = allergy_intolerance_resource
      result = SetByPath.set_by_path(resource, "code.text", "Peanut")
      assert_equal "Peanut", result["code"]["text"]
      assert_equal "Bee pollen", resource["code"]["text"], "original unchanged"

      result = SetByPath.set_by_path(resource, "code.coding[0].display", "Peanut")
      assert_equal "Peanut", result["code"]["coding"][0]["display"]
    end

    def test_allergy_intolerance_set_patient_reference
      resource = allergy_intolerance_resource
      result = SetByPath.set_by_path(resource, "patient.reference", "Patient/new-id")
      assert_equal "Patient/new-id", result["patient"]["reference"]

      result = SetByPath.set_by_path(resource, "AllergyIntolerance.patient", { "reference" => "Patient/au-core" })
      assert_equal "Patient/au-core", result["patient"]["reference"]
    end

    def test_allergy_intolerance_set_onset_datetime_choice_type
      resource = allergy_intolerance_resource
      result = SetByPath.set_by_path(resource, "onsetDateTime", "2024-01-15T10:00:00Z")
      assert_equal "2024-01-15T10:00:00Z", result["onsetDateTime"]

      result = SetByPath.set_by_path(resource, "onset[x]", "2024-01-01")
      assert_equal "2024-01-01", result["onset[x]"]
    end

    def test_allergy_intolerance_set_note_and_note_text
      resource = allergy_intolerance_resource
      result = SetByPath.set_by_path(resource, "note[0].text", "updated comment")
      assert_equal "updated comment", result["note"][0]["text"]

      result = SetByPath.set_by_path(resource, "AllergyIntolerance.note.text", "mandatory note text")
      assert_equal "mandatory note text", result["note"]["text"]
    end

    def test_allergy_intolerance_set_note_author_x_choice_type
      resource = allergy_intolerance_resource
      result = SetByPath.set_by_path(resource, "note[0].author[x]", { "reference" => "Practitioner/1" })
      assert_equal({ "reference" => "Practitioner/1" }, result["note"][0]["author[x]"])

      result = SetByPath.set_by_path(resource, "AllergyIntolerance.note.author[x]", { "reference" => "Patient/1" })
      assert_equal({ "reference" => "Patient/1" }, result["note"]["author[x]"])
    end

    def test_allergy_intolerance_set_reaction_manifestation_and_severity
      resource = allergy_intolerance_resource
      result = SetByPath.set_by_path(resource, "reaction[0].manifestation[0].text", "Hives")
      assert_equal "Hives", result["reaction"][0]["manifestation"][0]["text"]

      result = SetByPath.set_by_path(resource, "reaction[0].severity", "moderate")
      assert_equal "moderate", result["reaction"][0]["severity"]
    end

    def test_allergy_intolerance_set_meta_profile
      resource = allergy_intolerance_resource
      result = SetByPath.set_by_path(resource, "meta.profile[0]", "https://example.org/StructureDefinition/CustomAllergy")
      assert_equal "https://example.org/StructureDefinition/CustomAllergy", result["meta"]["profile"][0]
    end

    def test_allergy_intolerance_multi_set_by_path
      resource = allergy_intolerance_resource
      updates = [
        ["id", "all-multi-1"],
        ["AllergyIntolerance.patient.reference", "Patient/pat-multi"],
        ["note[0].text", "multi-set note"],
        ["reaction[0].manifestation[0].text", "Multi manifestation"],
        ["reaction[0].severity", "severe"]
      ]
      result = SetByPath.multi_set_by_path(resource, updates)
      assert_equal "all-multi-1", result["id"]
      assert_equal "Patient/pat-multi", result["patient"]["reference"]
      assert_equal "multi-set note", result["note"][0]["text"]
      assert_equal "Multi manifestation", result["reaction"][0]["manifestation"][0]["text"]
      assert_equal "severe", result["reaction"][0]["severity"]
      assert_equal "comment", resource["note"][0]["text"], "original unchanged"
    end

    def test_allergy_intolerance_creates_new_nested_arrays
      resource = allergy_intolerance_resource
      result = SetByPath.set_by_path(resource, "reaction[1].manifestation[0].text", "Second reaction")
      assert_equal 2, result["reaction"].length
      assert_equal "Rash", result["reaction"][0]["manifestation"][0]["text"]
      assert_equal "Second reaction", result["reaction"][1]["manifestation"][0]["text"]
    end

    def test_allergy_intolerance_full_path_with_resource_type_prefix
      resource = allergy_intolerance_resource
      result = SetByPath.set_by_path(resource, "AllergyIntolerance.code.text", "Full path code text")
      assert_equal "Full path code text", result["code"]["text"]
      result = SetByPath.set_by_path(resource, "AllergyIntolerance.reaction[0].manifestation[0].coding[0].display",
                                     "Full path display")
      assert_equal "Full path display", result["reaction"][0]["manifestation"][0]["coding"][0]["display"]
    end
  end
end
