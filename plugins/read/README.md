# Read plugin

Generates a read interaction test for every profile whose CapabilityStatement declares `read`. It is the host's built-in read test generation moved into a plugin, and the first test type to move. Once the built-in `ReadTestGenerator` is removed, this plugin is the only source of read tests.

## Enable it

```json
"plugins": {
  "read": { "builtin": "read" }
}
```

When this plugin is enabled, the host skips its built-in `ReadTestGenerator`, so the suite gets one read test per group, from the plugin. Without the plugin, the built-in read tests are generated as before.

Each read test goes where the built-in one was: first in delayed groups, otherwise right after the group's search tests, before include, Provenance revinclude, validation and must support tests. Those later tests check the resources the read test keeps in scratch.

First-class read profiles (`"first_class_profile": "read"` under `configs.profiles.<url>` or `configs.resources.<type>`) get an IDs input, with its default taken from the `read_ids.<snake_case type>` constant. The plugin reads these settings itself.

## What it generates

For each group with a read interaction:

- `<group dir>/<profile>_read_test.rb`, rendered from `templates/read.rb.erb`. It matches the built-in read test except that it includes this plugin's `InfernoSuitePlugins::Read::ReadTest` and has a `plugin_metadata` accessor that reads this plugin's section of the group's `plugins.yml`.
- `<suite dir>/plugins/read/read_test.rb`, a copy of `runtime/read_test.rb`, the module the read tests include.
- A `read` section in `<group dir>/plugins.yml`:

```yaml
read:
  interaction:
    code: read
    expectation: SHALL
  ids_input:          # only for first-class read profiles
    input_id: practitioner_ids
    title: Practitioner IDs
    description: Comma separated list of practitioner IDs that in sum contain all MUST SUPPORT elements
    default: alderson-helene
  tests:
  - id: au_core_v200_practitioner_read_test
    file_name: practitioner_read_test.rb
```

## Layout

- `lib/read/extractor.rb`: picks the groups with a read interaction and collects their expectation and IDs input
- `lib/read/test_generator.rb`: renders the template and places the test in the group; class names and test ids match the built-in generator
- `lib/read/plugin.rb`: `generate(context)` wires them together and installs the runtime
- `templates/read.rb.erb`: the generated test
- `runtime/read_test.rb`: what a read test does in Inferno: reads resources from scratch or from the IDs input and checks each response
- `test/read_plugin_test.rb`: generation, placement, and a check that the output matches the built-in `ReadTestGenerator`
- `test/runtime_read_test_test.rb`: the runtime module against a stand-in Inferno test

The runtime module still includes the gem's `InfernoSuiteGenerator::BasicTest`, the base every generated test uses for keeping resources and registering ids. The gem's own `InfernoSuiteGenerator::ReadTest` stays in the gem because its search tests use it.

## Test

```bash
bundle exec ruby -Ilib plugins/read/test/read_plugin_test.rb
bundle exec ruby -Ilib plugins/read/test/runtime_read_test_test.rb
```
