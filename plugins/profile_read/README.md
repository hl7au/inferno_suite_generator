# Profile read plugin

Generates one read test for every profile in the suite. The test reads each given id with `GET [base]/<type>/<id>`, checks the response and validates the resource against the profile. It doesn't depend on the generator's built-in read tests.

## Enable it

It ships with the generator. Add it to the generator config:

```json
"plugins": {
  "profile_read": { "builtin": "profile_read" }
}
```

## Options

| Option | Default | What it does |
|---|---|---|
| `declared_only` | `false` | Only generate tests for profiles whose resource declares `read` in the CapabilityStatement |
| `validate` | `true` | Validate each resource the server returns against the profile |

```json
"profile_read": { "builtin": "profile_read", "options": { "declared_only": true, "validate": false } }
```

## What it generates

For each group, for example `patient`:

- `patient/patient_profile_read_test.rb`: an Inferno test with id `<group id>_profile_read_test`, added at the end of the group's test list
- Its read data under `profile_read` in `patient/plugins.yml`:

```yaml
profile_read:
  resource_type: Patient
  profile_url: http://example.org/StructureDefinition/example-patient
  profile_version: 1.0.0
  expectation: SHALL
  example_ids:
  - pat-1
  validate: true
  tests:
  - id: example_v100_patient_profile_read_test
    file_name: patient_profile_read_test.rb
```

It also writes `<suite dir>/plugins/profile_read/profile_read_test.rb`, the module the generated tests run. So the suite runs without the plugin installed.

## What the test does in Inferno

- **Input:** `<group>_profile_read_ids`, a comma separated list of ids. It defaults to the ids of the IG examples whose `meta.profile` lists the profile, with or without a `|version`.
- **For each id:**
  - reads it and checks for HTTP 200, a resource of the profile's type and the same id
  - warns if the resource doesn't list the profile in `meta.profile`
  - validates it against `<profile url>|<profile version>`, unless `validate` is `false`
- **Result:**
  - fails once every id has been read, listing each id that failed and why
  - skips when no ids are given
  - is optional unless the CapabilityStatement says servers SHALL support read

## Test

```bash
bundle exec ruby -Ilib plugins/profile_read/test/plugin_test.rb
bundle exec ruby -Ilib plugins/profile_read/test/runtime_test.rb
```

`plugin_test.rb` runs the plugin through the host's loader. `runtime_test.rb` runs the Inferno module with Inferno's own assertions against a stubbed FHIR server.
