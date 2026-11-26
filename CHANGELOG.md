# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added `suite.validation_message_overrides` configuration option to change the severity of FHIR validator messages matched by regex (optionally narrowed by `from`, `location` and `message_id`). Implemented by `InfernoSuiteGenerator::ValidationMessageOverrides`, which generated suites extend their default validator with.
- Added `suite.fhirpathlab_serve_resources` configuration option (default `true`). Set to `false` to generate a suite without the FHIRPath Lab integration: it defines no `FHIRPATHLAB_URL`, registers no `/custom/<suite_id>/resources/...` route and adds no FHIRPath Lab links to result messages.
- Added `suite.groups_order` configuration option to control the order of `groups` in the generated `metadata.yml`. Profiles listed in `groups_order` are placed first in the given order, with any remaining profiles appended afterward in their existing relative order.
- Added shared `bin/hot-reload` dev-tooling asset and `InfernoSuiteGenerator::DevTools::HotReloadInstaller` to install/update it in a consumer test kit, replacing the copy-pasted watcher script previously maintained separately in each kit repo.
- Added `configs.generic.questionnaire_usage_tracing` to show questionnaires using each profile.
- Added `GroupMetadata#find_test` to find a group's tests by kind and details.
- Made the questionnaire element lists in group descriptions easier to read: the Must Support and "Elements not checked" lists give each item once with the elements it reads, items reading the same elements share a line, paths are grouped under a common prefix, and forms with shared items are listed together with an "Only in" line for the rest.

### Changed

- Tightened the `inferno_core` dependency to `~> 1.4`, `>= 1.4.1`: validation message overrides rely on the validator issue pipeline introduced in the 1.4 series.
- Relaxed `required_ruby_version` from `= 3.3.6` to `>= 3.3.6, < 3.4` so consumers can run any Ruby 3.3 patch release. Development, CI and the Docker image now use Ruby 3.3.12.

### Removed

- Removed the resource keeper: `InfernoSuiteGenerator::KeptResourcesRepository`, its `kept_fhir_resources` and `kept_resource_bodies` tables and the `RESOURCE_KEEPER_EXPIRATION_MS` setting. Newly generated suites require `utils/session_resource_endpoint.rb` and no longer register the `DELETE /custom/<suite_id>/resources/:session_id` route. A host that already has the two tables can drop them.

### Deprecated

- `utils/resource_keeper_endpoints.rb` and `InfernoSuiteGenerator::DeleteSessionResourcesEndpoint` remain only so suites generated before the resource keeper was removed still boot without regeneration. The endpoint now answers `204` without deleting anything, since served resources disappear with the session. `InfernoSuiteGenerator::KeptResourcesRepository` likewise remains as a no-op whose `save` and `save_all` store nothing, so test kits that call it directly (au-ps-inferno's `CompositionUtils`) keep running. All three will be removed in the next minor release; regenerate suites, or switch hand-written suites to `utils/session_resource_endpoint.rb`, before then.

### Fixed

- FHIRPath Lab links can now load the linked resource: generated suites wrap the `GET /custom/<suite_id>/resources/:session_id/:resource_type/:resource_id` route in `InfernoSuiteGenerator::FhirpathLabCors`, which answers the browser's `OPTIONS` preflight and sets `Access-Control-Allow-Origin` (with `Vary: Origin`) for the origin of `suite.fhirpathlab_url`. Test kits must regenerate their suites to pick this up.
- Resources served to FHIRPath Lab are no longer kept forever ([#53](https://github.com/hl7au/inferno_suite_generator/issues/53)). The route now reads them from the response bodies inferno-core already logs for the session (`InfernoSuiteGenerator::SessionResourceFinder`), so they disappear when the host deletes the session.
- `GeneratorConfigKeeper` no longer leaks config between instances in the same process.

## [0.2.0] - 2026-07-07

### Added

- Added `skip_generation` as a generator exclusion setting, while preserving backward compatibility with existing `skip` configurations.
- Added `exclude_slices_from_must_support` to control Must Support metadata extraction for specific slices.
- Added support for custom generators in validation test generation.
- Added `MSChecker` class for validating mandatory and must-support elements in FHIR resources, with configurable status messages for mandatory errors, optional warnings, and success indicators.
- Added Data Absent Reason (DAR) presence checks in `MSChecker` for both regular and primitive-typed elements.
- Added `Extensions` submodule in `MSChecker` to encapsulate extension presence checks.
- Added `Slices` submodule in `MSChecker` to encapsulate slice presence checks.
- Added configuration support in `MSChecker` to exclude USCDI-only tests via `exclude_uscdi_only`.
- Added primitive type handling and local field name resolution in FHIR resource navigation utilities.
- Added metadata parameter support to `FHIRResourceNavigation` methods for improved element resolution and value retrieval.
- Added unit tests for `MSChecker` DAR presence checks.
- Added unit tests for `FHIRResourceNavigation` methods.
- Added dynamic value resolution for configuration, supporting create-resource overrides with dynamic tokens (#20).
- Added references mapping to update tests, with a references keeper for tracking resolved references.
- Added readable resource type support to reference resolution tests.

### Changed

- Applied resource exclusion filtering more consistently across search test generators (`include`, `chain`, `multiple AND`, and `multiple OR`).
- Updated fixed-value search behavior to use configurable `fixed_values_to_search` definitions and better default parameter population for non-fixed inputs.
- Improved group metadata extraction by removing `ig_id` from group payloads and compacting nil reference target resource types.
- Refactored `MustSupportTest` to delegate element status checks to `MSChecker`, removing the `MustSupportHelpers` module.
- Refactored `resolve_path` and `get_next_value` in `FHIRResourceNavigation` to include DAR handling and improve element resolution logic.
- Refactored `available_resource_id_list` and update-test data normalization for consistent resource ID handling.
- Updated `inferno_core` dependency to version 1.0.6.

### Fixed

- Fixed include-search test generation to follow configured `extra_searches` entries with `type: include` and correct search-name matching.
- Fixed must-support slice validation failing for resources with repeated array elements by duplicating value definitions to ensure independence from array positions.
- Fixed reference metadata retrieval for the `Provenance` resource type to work correctly with class methods.
- Removed debug output from search test module execution.

## [0.1.0] - 2025-03-18

### Added

- Initial release of InfernoSuiteGenerator
- Automatic generation of Inferno test suites from FHIR Implementation Guide (IG) packages
- **Metadata extraction**: IG package loading, resource/profile extraction, search parameter extraction; outputs `metadata.yml`
- **Demodata extraction**: IG example/demo data extraction for create/update/patch tests; outputs `demodata.yml`
- **Test generators**:
  - Read tests (retrieve resources by ID)
  - Search tests (single and multiple OR/AND searches, chain searches, special identifier searches)
  - Provenance revinclude search tests
  - Include search tests (`_include` parameters)
  - Validation tests (resources validated against profiles)
  - Must Support tests (required elements present)
  - Reference resolution tests
  - Create tests (creating resources when applicable)
  - Update tests (updating resources to validate server behavior)
  - Patch tests
- **Suite structure**: Group generation by resource type and suite generation integrating all groups
- **Configuration**: JSON config with support for multiple config files (base + overrides merged in order)
- **Integration**: Generated suite can be added to the main Inferno application
- **Templates**: ERB-based templates for all generated test types
- **Core**: `GeneratorConfigKeeper`, config submodules (getters, extractors, generators, constants, utils), IG loader, and FHIR resource navigation utilities
- **Requirements**: Ruby 3.3.6

[0.2.0]: https://github.com/hl7au/inferno_suite_generator/releases/tag/v0.2.0
[0.1.0]: https://github.com/hl7au/inferno_suite_generator/releases/tag/v0.1.0
