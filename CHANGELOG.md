# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
