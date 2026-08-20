## InfernoSuiteGenerator

**InfernoSuiteGenerator** is a Ruby gem and Docker image for automatically generating Inferno test suites from FHIR Implementation Guides (IGs).

It analyzes an IG package, extracts profiles, search parameters and example data, and emits Ruby test classes/groups/suites ready to be plugged into an Inferno test kit.

It generates, among others:
- **Read tests** (retrieve by ID)
- **Search tests** (including multi-OR/AND, chained, identifier searches)
- **Validation tests** (profile validation)
- **Must Support tests** (required elements present)
- **Reference resolution tests**
- **Provenance `_revinclude` search tests**
- **`_include` search tests**
- **Create / Update / Patch tests** (where IG example data allows)

The primary audience is **IG authors and test-kit maintainers** who want to quickly stand up a high‑coverage Inferno suite for their IG, with contributors supported via a dedicated development section.

---

## Quickstart (IG authors)

### Requirements

- Ruby **3.3.6** (if using the gem directly)
- A FHIR IG package (e.g. `*.tgz` or unpacked package directory)
- A JSON configuration file describing how your IG maps to an Inferno suite
  (see `config.example.json` / `config.example2.json` in the repo)

You can run the generator either:
- **As a Ruby gem** inside a test kit project, or
- **Via Docker** using the published container image.

### Install as a gem

In your test kit’s `Gemfile`:

```ruby
gem "inferno_suite_generator"
```

Then:

```bash
bundle install
```

### Minimal Ruby usage example

```ruby
require "inferno_suite_generator"

# Single config
InfernoSuiteGenerator::Generator.generate(["config/your_suite_config.json"])

# Base + overrides, merged in order
InfernoSuiteGenerator::Generator.generate([
                                            "config/your_suite_config.base.json",
                                            "config/your_suite_config.version_specific.json"
                                          ])
```

After running, you will have:
- Extracted metadata (`metadata.yml`)
- Extracted demo/example data (`demodata.yml`)
- Generated tests, groups and suites wired into your test kit
---

## How generation works (high‑level)

Given one or more configuration files, the generator:

1. **Loads the IG package**
   Resolves profiles, search parameters, examples and other artifacts.
2. **Extracts metadata**
   Writes a consolidated `metadata.yml` describing resources, profiles and search parameters.
3. **Extracts demo/example data**
   Writes `demodata.yml` representing IG examples, used by create/update/patch tests.
4. **Generates tests**
   Creates Ruby test classes for:
    - Search / read / include / revinclude
    - Validation and must support
    - Reference resolution
    - Create / update / patch (when example data is available)
5. **Builds groups and suites**
   Groups tests by resource, composes them into suites, and wires them into your Inferno app.
6. **Integrates with your test kit**
   Uses templates and shared modules to emit code that fits Inferno’s conventions.

Internally, the project is organised as:
- **Main generator** (`lib/inferno_suite_generator.rb`) – orchestrates the flow above
- **Extractors** (`lib/inferno_suite_generator/extractors/`) – turn IG content into metadata and demo data
- **Test generators** (`lib/inferno_suite_generator/generators/`) – emit specific test types
- **Configuration/core** (`lib/inferno_suite_generator/core/`) – configuration loading, merging and helpers
- **Templates** (`lib/inferno_suite_generator/templates/`) – ERB templates that define the emitted Ruby
- **Shared test modules** (`lib/inferno_suite_generator/test_modules/`) – common behavior for generated tests

---

## Configuration overview

The generator is driven by one or more JSON configuration files. You always pass an **array of config paths**; if there is only a single file it is still wrapped in an array, and when multiple are given they are **deep‑merged in order** (later overrides earlier).

There are two example configurations in the project root:
- `config.example.json`
- `config.example2.json`

At a high level, a config file contains:
- **`ig`** – which IG this suite targets
- **`suite`** – how the top‑level Inferno suite looks and behaves
- **`constants`** – reusable values for IDs, search defaults, comparators, etc.
- **`configs.generic`** – global behavior tweaks and custom generators
- **`configs.profiles`** – per‑profile overrides
- **`configs.resources`** – per‑resource overrides (by FHIR resource type)

### IG section

- **`id`**: Implementation Guide ID
- **`version`**: IG version
- **`name`**: Human‑readable name
- **`link`**: IG documentation URL
- **`cs_profile_url`**: CapabilityStatement profile URL
- **`cs_version_specific_url`**: Version‑specific CapabilityStatement URL

### Suite section

- **`title`**: Test suite title (also used to derive Ruby module names and paths)
- **`extra_json_paths`**: Additional JSON configs to merge
- **`tx_server_url`**: Terminology server URL used by generated tests
- **`snomed_edition`**: SNOMED CT edition the validator resolves version-less `http://snomed.info/sct` codes against, emitted as `cliContext.snomedCT`. An edition SCTID, or an alias such as `au`, `us`, `uk`, `intl`. Defaults to `au`. Must match an edition the configured `tx_server_url` actually carries: the validator otherwise fails every SNOMED lookup with "A definition for CodeSystem 'http://snomed.info/sct' version 'null' could not be found" and then reports valid codes as absent from their value sets.
- **`fhirpathlab_url`**: Base URL of a [FHIRPath Lab](https://fhirpath-lab.com/) instance used to turn FHIRPath locations in result messages into interactive debugging links (see [Linking FHIRPath locations to FHIRPath Lab](#linking-fhirpath-locations-to-fhirpath-lab)). Defaults to `https://fhirpath-lab.com/`. Overridable per deployment via the `FHIRPATHLAB_URL` env var.
- **`links`**: Links shown in the Inferno UI (e.g. “Report Issue”, “IG Documentation”)
- **`outer_groups`**: Extra groups to include before/after generated groups:
    - `import_type`
    - `import_path`
    - `group_position` (`before` / `after`)
    - `group_id`

> **Note**: Module names and paths are derived from `suite.title`. You do **not** need to set `suite_module_name`, `module_name_prefix`, `test_id_prefix` or explicit code paths.

### Constants section

- **`default_fhir_server`**: Default FHIR server URL used in inputs
- **`read_ids.<resource>`**: Default IDs for first‑class read/search tests (e.g. `read_ids.patient`)
- **`patch_ids.<resource>`**: Default IDs for patch tests
- **`search_default_values.*`**: Named sets of default values for date/datetime/code search params
- **`search.comparators`**: Allowed comparators for date/datetime params (`gt`, `lt`, `ge`, `le`, etc.)

These constants can be referred to from profile/resource configs, allowing you to centralise and reuse values.

### Configs – generic section

- **`expectation`**: Allowed expectation levels (e.g. `["SHALL", "SHOULD", "MAY"]`)
- **`search_params_to_ignore`**: Search parameters to ignore when generating tests (e.g. `["_sort"]`)
- **`register_generators`**: Custom generators to load, each with:
    - `path_to_generator`
    - `generator_class`
    - `path_to_template`
    - `test_type` (e.g. `"search"`)
When the IG has **no CapabilityStatement** (e.g. AU PS, IPS), groups are built automatically from every profile `StructureDefinition` found in the loaded IG resources (`kind = "resource"` and `derivation = "constraint"`), grouped by resource type. This is only consulted when `ig_resources.cs_resources` is empty — IGs that publish a CapabilityStatement are unaffected, and no config is needed to opt in. Because there's no CapabilityStatement to source them from, groups built this way have no interactions, operations, or searches — only must‑support elements, mandatory elements, terminology bindings, and references. If the IG has neither a CapabilityStatement nor any profile StructureDefinitions, no groups are generated and a warning is logged.

### Configs – profiles section

Keyed by **profile URL**; lets you tune or override behavior for specific profiles:

- **`keep_all_search_results`**: Keep all search results in Inferno scratch
- **`skip`**: Skip this profile entirely (metadata extraction and generation)
- **`skip_generation`**: Skip generation only (tests/groups/suite), while still keeping metadata extraction
- **`first_class_profile`**: Mark as first‑class `read` or `search`
- **`override_executor.search.<param>`**: Swap executors for specific search parameters
- **`forced_initial_search`**: Force initial search params (e.g. `["patient", "code"]`)
- **`register_extractors`**: Register custom extractors with:
    - `path_to_extractor`
    - `extractor_class`
    - `extractor_type` (e.g. `"must_support"`)
- **`extra_searches`**: Describe additional searches to generate, such as:
    - `{ "type": "search", "params": ["_id"] }`
    - `{ "type": "include", "param": "medication", "target_resource": "Medication", "paths": ["medicationReference"] }`
- **`search_param.<id>`**: Per‑search‑parameter options:
    - `default_values` (constant key or explicit list)
    - `multiple_and_expectation` / `multiple_or_expectation`
    - `comparators`
    - `expectation_change` (e.g. `{ "from": "SHALL", "to": "SHOULD" }`)
- **`create_resource_overrides`**: Map of FHIRPath → value applied to the resource body before a create request is sent.
  Values support `${Time.now}` and `${DateTime.now}` tokens (resolved at test runtime), e.g.:
  ```json
  "create_resource_overrides": { "dateAsserted": "${Time.now}" }
  ```
- **`must_support.remove_elements`**: Optional rules for trimming must‑support elements
- **`slice_discriminator_default_value`**: Defaults for value‑type slice discriminators; an array of objects with:
    - `slice_id`
    - optional `discriminator_path`
    - `value`: array of `{ "path": "...", "value": ... }`, where inner `value` may be scalar or an array

### Configs – resources section

Keyed by FHIR **resource type** (e.g. `"Observation"`, `"MedicationRequest"`). Options largely mirror the profile‑level settings, but apply to all profiles of that resource type:

- All options from **profiles** (other than the URL key), including `skip` and `skip_generation`
- **`search_multiple_or_and_by_target_resource`**: Configure multi‑OR/AND behavior for target‑resource params
- **`search.test_medication_inclusion`**: Enable special include tests for Medication where applicable

See `config.example.json` and `config.example2.json` for a fully worked example.

---

## Saving fetched resources (Resource Keeper)

Every generated suite automatically keeps a copy of every FHIR resource it reads (via `read`, `search`, or reference resolution), keyed by the current test session — no configuration or tester interaction required. Storage is in-process: resources live in two tables in the same database inferno-core already uses (`kept_resource_bodies` and `kept_fhir_resources`, created on first use — see `InfernoSuiteGenerator::KeptResourcesRepository`), and are exposed at `/custom/<suite_id>/resources/...` (see `InfernoSuiteGenerator::SaveResourceEndpoint`/`FetchResourceEndpoint`/`DeleteSessionResourcesEndpoint` in [`resource_keeper_endpoints.rb`](lib/inferno_suite_generator/utils/resource_keeper_endpoints.rb)). Saving is best‑effort and never affects test results.

Kept resources expire after `RESOURCE_KEEPER_EXPIRATION_MS` milliseconds (env var, default `604800000` / 7 days) — an expired resource is served as a 404, but its row is not deleted. `DELETE /custom/<suite_id>/resources/:session_id` removes a session's *references* to its resources (rows in `kept_fhir_resources`), which is enough to make them unreachable via this API; it does **not** purge the underlying resource bodies from `kept_resource_bodies` — those are content-addressed and shared across sessions (see below), so they're left in place indefinitely rather than garbage-collected. This endpoint is not a data-erasure mechanism.

Storage is deduplicated by content hash: identical resource bodies (e.g. the same resource fetched across many sessions against a stable test server) share a single row in `kept_resource_bodies` instead of being stored once per session.

---

## Linking FHIRPath locations to FHIRPath Lab

Validation messages that inferno-core adds to a result generally look like this:

```
Patient/123: Patient.name[0].given: Minimum required = 1, but only found 0
```

i.e. `<ResourceType>/<resource_id>: <path>: <detail>`. Every generated suite monkeypatches `Inferno::DSL::Messages#add_message` (see `InfernoSuiteGenerator::MessagesFhirpathLabPatch` in [`fhirpath_lab_message_linker.rb`](lib/inferno_suite_generator/utils/fhirpath_lab_message_linker.rb)) so that whenever a message matches this shape, `<path>` is rewritten into a link to [FHIRPath Lab](https://fhirpath-lab.com/), pre-loaded with the failing expression and the resource it was evaluated against:

```
Patient/123: [Patient.name[0].given](https://fhirpath-lab.com?expression=...&engine=fhirpath.js&resource=...): Minimum required = 1, but only found 0
```

This is a general-purpose patch: it applies to any message text passing through `add_message` (validator issues, `perform_additional_validation` results, custom test messages, etc.) — not just a specific validator code path — so long as the text matches the `<ResourceType>/<resource_id>: <path>: <detail>` pattern.

The `resource=` link points at the resource's entry in the [Resource Keeper](#saving-fetched-resources-resource-keeper), so linking is only applied when `fhirpathlab_url` is configured and a resource was actually saved for the current test session — otherwise messages are left untouched.

---

## Using the gem in a test kit

In a typical Inferno test kit repo you will:

1. Add `inferno_suite_generator` to the `Gemfile`.
2. Create one or more config files under `config/`.
3. Add a small Ruby script or Rake task that calls:

```ruby
InfernoSuiteGenerator::Generator.generate(["config/your_ig.json"])
   ```

4. Run that script to generate tests/groups/suites into your test kit’s structure.
5. Commit the generated code (or generate in CI as part of the build).

You can re‑run the generator whenever the IG or configuration changes; it’s designed to be part of your regular workflow.

---

## Development & CI (for contributors)

### Local development

After checking out the repo:

```bash
bin/setup
```

This installs dependencies and prepares the project. You can then use:

- `bin/console` – interactive Ruby console with the gem loaded

### Ruby and dependencies

- This gem targets **Ruby 3.3.6** (see `inferno_suite_generator.gemspec`).
- Dependencies include `deep_merge`, `inferno_core`, and `jsonpath`; see the gemspec for exact versions.

### Project structure (internal)

- **Main module**: `InfernoSuiteGenerator` contains the overall orchestration
- **Generator**: coordinates extraction, metadata, test generation and suite creation
- **Test generators**: inherit from a basic generator and implement each test type
- **Extractors**: handle metadata and demo data extraction
- **Configuration**: registry‑style configuration system with helpers under `lib/inferno_suite_generator/core/`

When modifying or extending:
- **Follow existing naming and structure patterns**
- **Keep generators focused** (single responsibility)
- **Prefer overriding hook methods** over changing global algorithms
- **Update templates** when you change generated code shape

### CI

GitHub Actions CI (`.github/workflows/ci.yml`) runs on every push and executes:

- **RuboCop**: `make docker-lint`
- **Reek**: `make docker-reek`
- **Fasterer**: `make docker-fasterer`
- **Steep type checking**: `make docker-typecheck`
- **Tests**: `make docker-tests`

These use Docker for a consistent environment. For local equivalents, you can run:

- `make lint`
- `make reek`
- `make fasterer`
- `make typecheck`
- `make tests`
- or `make check` to run them all.

## Changelog

See `CHANGELOG.md` in the repository for version history.

## License

The gem is available as open source under the terms of the **Apache 2.0** license.

## Code of Conduct

Everyone interacting in this project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the project’s Code of Conduct (`CODE_OF_CONDUCT.md` in the repository).