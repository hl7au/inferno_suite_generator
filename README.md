# InfernoSuiteGenerator

A Ruby gem for automatically generating test suites for FHIR Implementation Guides (IGs) to be used with the Inferno testing framework.

## Description

InfernoSuiteGenerator is a tool that simplifies the creation of test suites for validating FHIR resources against Implementation Guides. It analyzes FHIR Implementation Guide packages and generates Ruby test classes for the Inferno testing framework.

The generator creates various types of tests:
- Read tests (retrieving resources by ID)
- Search tests (including multiple OR/AND searches, chain searches, special identifier searches)
- Validation tests (validating resources against profiles)
- Must Support tests (verifying required elements are present)
- Reference resolution tests (ensuring references can be resolved)
- Provenance revinclude search tests (searching for Provenance resources)
- Include search tests (testing _include parameters)
- Create tests (creating resources for testing when applicable)
- Update tests (updating resources to validate server behavior)
- Patch tests

## Project Structure

The project is organized into several key components:

- **Main Generator** (`lib/inferno_suite_generator.rb`): Orchestrates the entire generation process
- **Metadata Extractors** (`lib/inferno_suite_generator/extractors/`): Extract information from FHIR IGs
- **Test Generators** (`lib/inferno_suite_generator/generators/`): Create specific types of tests
- **Configuration System** (`lib/inferno_suite_generator/core/`): `GeneratorConfigKeeper` and config submodules (`config/getters.rb`, `config/extractors.rb`, `config/generators.rb`, `config/constants.rb`, `config/utils.rb`) manage settings and customizations
- **Template System** (`lib/inferno_suite_generator/templates/`): Uses ERB templates to generate Ruby code
- **Test Modules** (`lib/inferno_suite_generator/test_modules/`): Provide common functionality for generated tests
- **Utilities** (`lib/inferno_suite_generator/utils/`): Helper functions and constants

## Requirements

- Ruby 3.3.6 (see `inferno_suite_generator.gemspec`)

## Installation

Add this line to your application's Gemfile:

```ruby
gem "inferno_suite_generator"
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install inferno_suite_generator
```

## Usage

### Basic Usage

1. Create a configuration file (`config.json`) with your Implementation Guide settings (see Configuration section below)
2. Run the generator:

```ruby
require "inferno_suite_generator"

# One config
InfernoSuiteGenerator::Generator.generate(["path/to/config.json"])

# Or two configs (base + overrides), merged in order
InfernoSuiteGenerator::Generator.generate(["path/to/base.json", "path/to/overrides.json"])
```

This will:
- Load the IG package
- Extract metadata about resources and profiles
- Generate test files for various FHIR interactions
- Organize tests into groups and suites
- Add the generated test suite to your Inferno application

### Generation Process

The generator follows these steps:

1. **Load IG Package**: Loads the FHIR Implementation Guide package
2. **Extract Metadata**: Extracts information about resources, profiles, and search parameters (writes `metadata.yml`)
3. **Extract Demodata**: Extracts IG example/demo data used by create/update/patch tests (writes `demodata.yml`)
4. **Generate Tests**: Creates various types of tests based on the metadata
   - Search tests (including specialized search types)
   - Read tests
   - Provenance revinclude search tests
   - Include search tests
   - Validation tests
   - Must Support tests
   - Reference resolution tests
   - Create tests
   - Update tests
   - Patch tests
5. **Generate Groups**: Organizes tests into groups by resource type
6. **Generate Suites**: Creates a test suite that includes all the groups
7. **Integrate with Inferno**: Adds the generated suite to the main Inferno application

## Configuration

The configuration file (`config.json`) controls how the generator works. Pass an **array of config file paths** (at least one) to `generate`; multiple configs are deep-merged in order, so later configs override earlier ones (e.g. a base config plus a local overrides file). See the example configurations at the project root: `config.example.json` and `config.example2.json`. Here's an example configuration with explanations:

```json
{
  "ig": {
    "id": "your_ig_id",
    "version": "1.0.0",
    "name": "Your IG Name",
    "link": "https://example.com/your-ig",
    "cs_profile_url": "http://example.com/fhir/CapabilityStatement/your-ig-server",
    "cs_version_specific_url": "https://example.com/your-ig/1.0.0/CapabilityStatement-your-ig-server.html"
  },
  "suite": {
    "title": "Your IG Title",
    "extra_json_paths": ["extra-config.json"],
    "tx_server_url": "https://tx.fhir.org/r4",
    "outer_groups": [
      {
        "import_type": "relative",
        "import_path": "../../custom_groups/capability_statement/capability_statement_group",
        "group_position": "before",
        "group_id": "your_capability_statement_group"
      }
    ],
    "links": [
      {
        "label": "Report Issue",
        "url": "https://github.com/your-org/your-repo/issues"
      },
      {
        "label": "Your IG",
        "url": "https://example.com/your-ig"
      }
    ]
  },
  "constants": {
    "default_fhir_server": "https://example.com/fhir",
    "read_ids.patient": "patient1, patient2",
    "search_default_values.diagnostic_result": ["251739003", "24701-5"],
    "search_default_values.date": ["ge1950-01-01", "le2050-01-01", "gt1950-01-01", "lt2050-01-01"],
    "search_default_values.datetime": [
      "ge1950-01-01T00:00:00.000Z",
      "le2050-01-01T23:59:59.999Z",
      "gt1950-01-01T00:00:00.000Z",
      "lt2050-01-01T23:59:59.999Z"
    ],
    "search.comparators": ["gt", "lt", "ge", "le"]
  },
  "configs": {
    "generic": {
      "expectation": ["SHALL", "SHOULD", "MAY"],
      "search_params_to_ignore": ["count", "_sort", "_include"],
      "register_generators": [
        {
          "path_to_generator": "lib/your_test_kit/generators/custom_identifier_search/generator.rb",
          "generator_class": "InfernoSuiteGenerator::Generator::SpecialIdentifierSearchTestGenerator",
          "path_to_template": "lib/your_test_kit/generators/custom_identifier_search/template.rb.erb",
          "test_type": "search"
        }
      ]
    },
    "profiles": {
      "http://example.com/fhir/StructureDefinition/your-profile": {
        "first_class_profile": "search",
        "override_executor": {
          "search": {
            "identifier": "run_search_test_with_system"
          }
        },
        "register_extractors": [
          {
            "path_to_extractor": "lib/your_test_kit/extractors/ms_delete/extractor.rb",
            "extractor_class": "InfernoSuiteGenerator::Generator::MustSupportDeleteExtractor",
            "extractor_type": "must_support"
          }
        ],
        "extra_searches": [
          { "type": "search", "params": ["_id"] },
          {
            "type": "include",
            "param": "medication",
            "target_resource": "Medication",
            "paths": ["medicationReference"]
          }
        ]
      }
    },
    "resources": {
      "Observation": {
        "keep_all_resources_on_search": true,
        "forced_initial_search": ["patient", "code"],
        "search_param": {
          "clinical-date": {
            "default_values": "search_default_values.datetime",
            "multiple_and_expectation": "SHOULD",
            "comparators": "search.comparators"
          },
          "Observation-status": {
            "multiple_or_expectation": "SHALL"
          },
          "clinical-code": {
            "multiple_or_expectation": "SHOULD"
          }
        }
      },
      "MedicationRequest": {
        "search": { "test_medication_inclusion": true },
        "search_param": {
          "MedicationRequest-authoredon": {
            "default_values": "search_default_values.datetime",
            "multiple_and_expectation": "SHOULD",
            "comparators": "search.comparators"
          },
          "MedicationRequest-intent": { "multiple_or_expectation": "SHOULD" }
        }
      },
      "Medication": { "skip": true }
    }
  }
}
```

### Configuration Options

#### IG Section
- `id`: The ID of the Implementation Guide
- `version`: The version of the Implementation Guide
- `name`: The name of the Implementation Guide
- `link`: The URL to the Implementation Guide
- `cs_profile_url`: The URL to the CapabilityStatement profile
- `cs_version_specific_url`: The URL to the version-specific CapabilityStatement

#### Suite Section
- `title`: The title of the test suite (also used to derive module name and paths automatically)
- `extra_json_paths`: Additional JSON configuration files to merge
- `tx_server_url`: Terminology server URL used by generated tests
- `links`: Links to be included in the test suite UI
- `outer_groups`: Additional groups to include before/after generated groups
  - `import_type`: How to import the group (e.g., `relative`)
  - `import_path`: Path to the external group file
  - `group_position`: Where to place it (`before` or `after`)
  - `group_id`: The group ID to reference

Note: Module names and paths are derived from `suite.title`; you do not need to set `suite_module_name`, `module_name_prefix`, `test_id_prefix`, or explicit paths.

#### Constants Section
- `default_fhir_server`: Default FHIR server URL used for inputs
- `read_ids.<resource>`: Default IDs for first-class read/search tests (e.g., `read_ids.patient`)
- `patch_ids.<resource>`: Default IDs for patch tests (e.g., `patch_ids.patient`)
- `search_default_values.*`: Named sets of default values used in search tests
- `search.comparators`: Allowed comparators for date/datetime searches

#### Configs Section
- `generic`: Global settings
  - `expectation`: Allowed expectation levels (e.g., `SHALL`, `SHOULD`, `MAY`)
  - `search_params_to_ignore`: Search params to ignore when generating tests
  - `register_generators`: Custom generators to load
    - `path_to_generator`, `generator_class`, `path_to_template`, `test_type`
- `profiles`: Per-profile overrides (keyed by profile URL)
  - `skip`: Skip generating tests for this profile
  - `first_class_profile`: Mark as first-class `read` or `search`
  - `override_executor.search.<param>`: Override executor for specific search param
  - `forced_initial_search`: Force initial search params (e.g., `["patient", "code"]`)
  - `register_extractors`: Register custom extractors
    - `path_to_extractor`, `extractor_class`, `extractor_type`
  - `extra_searches`: Additional searches to generate
    - `{ "type": "search", "params": ["_id"] }`
    - `{ "type": "include", "param": "medication", "target_resource": "Medication", "paths": ["medicationReference"] }`
  - `search_param.<id>`: Per-search-parameter options
    - `default_values`: Named constant key or explicit list
    - `multiple_and_expectation` / `multiple_or_expectation`
    - `comparators`: Allowed comparators for that param
    - `expectation_change`: `{ from: "SHALL", to: "SHOULD" }`
  - `must_support.remove_elements`: Optional removal rules for must support
  - `keep_all_resources_on_search`: When `true`, every search for this profile saves all returned resources to scratch (for use by later tests). When unset or `false`, only the first search in the sequence saves to scratch.
- `resources`: Per-resource overrides (keyed by resource type)
  - All the same options as `profiles` (without profile URL)
  - `search_multiple_or_and_by_target_resource`: Configure multi-OR/AND behavior for target resource params
  - `search.test_medication_inclusion`: Enable special include tests for Medication where applicable
  - `keep_all_resources_on_search`: When `true`, every search for this resource saves all returned resources to scratch (same behavior as under `profiles`).

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

### Project Structure

The project follows a clear organization pattern:

1. **Main Module**: `InfernoSuiteGenerator` module contains all classes
2. **Generator Class**: Main orchestrator that coordinates the entire process
3. **Test Generators**: Inherit from `BasicTestGenerator` and implement specific test types
4. **Metadata Extractors**: Extract and process metadata from FHIR IGs
5. **Configuration**: Uses Registry pattern for global configuration

### Docker

The InfernoSuiteGenerator is available as a Docker image from GitHub Container Registry. This allows you to run the generator without setting up a Ruby environment.

#### Using the Docker Image

Pull the latest image:

```bash
docker pull ghcr.io/beda-software/inferno_suite_generator:latest
```

Run the generator with your configuration file:

```bash
docker run -v $(pwd):/data ghcr.io/beda-software/inferno_suite_generator:latest /data/config.json
```

This mounts your current directory to `/data` in the container and runs the generator with your configuration file. The image passes the first argument as the config path; for multiple config files (base + overrides), use the Ruby API instead.

#### Building the Docker Image Locally

You can also build the Docker image locally:

```bash
docker build -t inferno_suite_generator .
```

And run it:

```bash
docker run -v $(pwd):/data inferno_suite_generator /data/config.json
```

### CI

The project uses GitHub Actions for continuous integration:

- **Lint**: RuboCop (`make docker-lint`)
- **Reek**: Code smell checks (`make docker-reek`)
- **Fasterer**: Performance checks (`make docker-fasterer`)
- **Type checking**: Steep (`make docker-typecheck`)
- **Tests**: Rake test suite (`make docker-tests`)

All CI steps run in Docker via these Make targets for a consistent environment. Local alternatives: `make lint`, `make reek`, `make fasterer`, `make typecheck`, `make tests`; or `make check` to run all.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/beda-software/inferno_suite_generator. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/beda-software/inferno_suite_generator/blob/main/CODE_OF_CONDUCT.md).

### Best Practices for Modifying the Codebase

1. **Respect the patterns**: Follow existing patterns for naming, organization, and inheritance
2. **Maintain separation of concerns**: Keep generators focused on single responsibilities
3. **Preserve the template method pattern**: Override specific methods rather than changing the overall algorithm
4. **Update templates appropriately**: Ensure any changes are reflected in templates

## Changelog

See [CHANGELOG.md](https://github.com/hl7au/inferno_suite_generator/blob/main/CHANGELOG.md) for version history.

## License

The gem is available as open source under the terms of the [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Code of Conduct

Everyone interacting in the InfernoSuiteGenerator project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/beda-software/inferno_suite_generator/blob/main/CODE_OF_CONDUCT.md).