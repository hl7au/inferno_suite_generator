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
  end
end
