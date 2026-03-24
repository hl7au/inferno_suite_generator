# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-03-24

### Changed

- Fixed extra include tests.
- Added the ability to use a custom generator for validation tests.

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

[0.1.1]: https://github.com/hl7au/inferno_suite_generator/releases/tag/v0.1.1
[0.1.0]: https://github.com/hl7au/inferno_suite_generator/releases/tag/v0.1.0
