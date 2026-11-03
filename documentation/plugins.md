# Plugins: a simple guide

## Why we need it

The generator builds an Inferno test suite from an IG. It has a fixed set of built-in tests, such as search, read, validation and Must Support.

Sometimes a team needs more than that:

- a test that only makes sense for their IG
- extra data in the suite, for example which forms use a profile
- extra text in a group's or a test's description in Inferno

Without plugins, the only ways to get this are to fork the generator or to use `configs.generic.register_generators`, which still works. A plugin does it from its own folder or gem, with its own version, tests and docs. The host's code stays the same, and so do its `metadata.yml` and `demodata.yml`.

## What a plugin can add

A plugin gets everything the host has built: the IG resources, the metadata, the demo data, the config and the output folder. It can add four kinds of **outputs** to the generated suite.

| Output | What it is | Example |
|---|---|---|
| **Data** | Entries in `plugins.yml`, in the suite folder or a group folder | the questionnaires that use the `Patient` profile |
| **Tests** | A test file in a group folder, added to the group's test list | `patient_read_test.rb` in the `patient` group |
| **Description text** | Markdown at the end of a group's or a test's description in Inferno | a "Used in questionnaires" section |
| **Runtime files** | Code the generated tests need when Inferno runs them | `<suite dir>/plugins/read/read_test.rb` |

## What a plugin is

A plugin is a folder, or a gem, with two things:

1. **A `plugin.yml` manifest** at its root:

   ```yaml
   id: read                                  # snake_case, the same id as in the config
   name: Read tests
   version: 0.1.0
   entrypoint: lib/read.rb                   # the file the host requires
   class: InfernoSuitePlugins::Read::Plugin  # the class the host creates
   host_version: ">= 0.1.0"                  # optional
   ```

2. **A class with a `generate(context)` method.** The host creates it with no arguments and calls `generate` once per run. Inheriting from `Plugins::Base` is optional.

   ```ruby
   module InfernoSuitePlugins
     module Read
       class Plugin < InfernoSuiteGenerator::Plugins::Base
         def generate(context)
           data_by_group = Extractor.extract(context)       # this plugin's data for each group
           context.metadata.groups(data_by_group)           # -> data in each group's plugins.yml
           TestGenerator.generate(context, data_by_group)   # -> one test per group
           context.install_runtime                          # -> runtime files in the suite
         end
       end
     end
   end
   ```

All plugins load into one Ruby process. Keep each plugin's code under `InfernoSuitePlugins::<CamelCaseId>`, so its names don't clash with other plugins or the host.

## How it works

The plugin steps fit into the host's run like this:

```
load_plugins       <- Step 1
load_ig_package
extract_metadata   writes metadata.yml
extract_demodata   writes demodata.yml
built-in tests
run_plugins        <- Steps 2 and 3
generate_groups    <- Step 4
generate_suites
```

### Step 1. Load the plugins

Before the IG is loaded, the host reads the `plugins` section of the config. For each enabled entry, it:

- finds the plugin's folder
- reads `plugin.yml` and checks it
  - the required keys are there: `id`, `name`, `version`, `entrypoint`, `class`
  - the `id` is snake_case and matches the key in the config
  - `host_version`, if set, matches the installed generator
- requires the entrypoint and creates the class
- checks that `generate` takes one argument

Any problem stops the run here, before the slow IG work starts. For example:

```
Plugin "local" is configured, but its plugin.yml says id "read"
```

### Step 2. Run the plugins

After the host has generated its built-in tests, it calls `generate(context)` on each plugin, in config order. A plugin sees the tests that the host and earlier plugins have added.

The `context` holds everything the plugin needs:

- **Inputs:** `ig_resources`, `ig_metadata`, `ig_demodata`, `config`, `base_output_dir`
- **The plugin's own settings:** `manifest` and `options`
- **The groups to work on:** `context.groups`. These are the IG's groups minus the ones the config skips.
- **A way to find a group's tests:** `context.test_index(group)`
- **Writers for the outputs:** `context.metadata` and `context.descriptions`

### Step 3. Collect the outputs

Each output has its own tool:

- **Data:** `context.metadata.group(group, data)`, `.groups(data_by_group)` or `.suite(data)`.
  - Everything goes under the plugin's id, so many plugins share one `plugins.yml`.
  - If a plugin writes to the same file twice, hashes merge, lists are joined and other values are replaced.
  - The files are written once, after the last plugin.
- **Tests:** a subclass of `Plugins::TestGenerator`.
  - It renders one ERB template per group and writes the test file into the group folder.
  - It adds the test to the group's test list, at the end by default. Override `insert_index` to put it somewhere else.
  - It also lists the test under `tests` in the plugin's section of `plugins.yml`.
- **Description text:** `context.descriptions.group(group, markdown)`, `.groups(markdown_by_group)` or `.test(group, test_id, markdown)`.
  - Pass plain Markdown. The host escapes it for the group template.
  - Blank text is ignored.
- **Runtime files:** `context.install_runtime` copies the plugin's `runtime/` folder to `<suite dir>/plugins/<id>/`. A generated test can then `require_relative '../plugins/<id>/<file>'`, and the suite works without the plugin installed.

A generated test reads its plugin's data back at run time:

```ruby
InfernoSuiteGenerator::Plugins::RuntimeMetadata.load(__dir__, "read") # this group's "read" section
```

### Step 4. Build the groups

Groups are generated after the plugins run. So every test a plugin added is in its group's test list, and Inferno runs it.

Each group's description is the built-in text, a blank line, then the plugins' text in config order. A test's description works the same way: its own text, then the plugins' text. A group or test that gets no plugin text keeps exactly the description it had before.

## Options

Add a `plugins` section to any config file. Each entry is keyed by the plugin's id and names exactly **one source**:

```json
"plugins": {
  "local":  { "path": "plugins/local", "options": { "strict": true } },
  "shared": { "gem": "isg_shared_plugin" }
}
```

| Source | Where the plugin is |
|---|---|
| **path** | a folder, relative to the working directory |
| **gem** | the root of an installed gem that ships `plugin.yml` |
| **builtin** | `plugins/<name>` inside this gem. The gem ships no built-in plugins yet, so this source currently fails with "Plugin manifest not found". |

Other settings:

- **`options`**: any hash. The plugin gets it as `context.options`.
- **`enabled`**: set it to `false` to turn a plugin off without removing it.

The section is keyed by id, so a later config file can change one plugin's entry. For example, it can turn off a plugin that an earlier file turned on:

```json
"plugins": {
  "local": { "enabled": false }
}
```

## Make a new plugin

1. Create the skeleton. In a test kit, call `Scaffold` directly:

   ```bash
   bundle exec ruby -e 'require "inferno_suite_generator/plugins/scaffold"; puts InfernoSuiteGenerator::Plugins::Scaffold.new(id: "my_plugin", destination: "plugins/my_plugin").create'
   ```

   In this repository, use the Rake task. It isn't available in a test kit.

   ```bash
   bundle exec rake 'plugins:new[my_plugin]'   # creates plugins/my_plugin
   ```

   The skeleton has `plugin.yml`, a Plugin class, an Extractor, a test, a README and an AGENTS.md. It runs as it is: it writes each group's resource type and profile URL to `plugins.yml`.

2. Write the plugin's tests with `Plugins::Testing`. `run_plugin` loads the plugin the way the host does and runs it into a temporary folder:

   ```ruby
   require "inferno_suite_generator/plugins/testing"

   include InfernoSuiteGenerator::Plugins::Testing

   group = build_group_metadata(interactions: [{ code: "read", expectation: "SHALL" }])
   descriptions = run_plugin(PLUGIN_ROOT, ig_metadata: build_ig_metadata(groups: [group]), base_output_dir: dir)
   plugin_metadata(File.join(dir, "patient"), "my_plugin")   # => the plugin's data for the group
   descriptions.for(group)                                   # => the Markdown it added to the group
   descriptions.for_test(group, test_id)                     # => the Markdown it added to one test
   ```

3. Run the tests.

   ```bash
   bundle exec ruby -Ilib -Iplugins/my_plugin/test plugins/my_plugin/test/my_plugin_test.rb
   ```

   In this repository, `bundle exec rake test` also runs `plugins/*/test/**/*_test.rb`.

## Ship a plugin as a gem

Put `plugin.yml` at the gem root and include it, the templates and the runtime files in `spec.files`. Users then enable it with `{ "gem": "<gem name>" }`. Depend on `inferno_suite_generator` in the gemspec, and set `host_version` in `plugin.yml` to the range you test against.

## What a plugin can't do

These cases are not allowed, or have no effect:

- **Change `metadata.yml` or `demodata.yml`.** The host writes them before plugins run. Plugin data goes to `plugins.yml`.
- **Change the built-in description.** A plugin can only add text after it. It can't change, remove or reorder the built-in sections.
- **Add a test with an id the group already has.** `TestGenerator` raises `Plugins::Error` if the host or another plugin already added that test. Turn off one of the two.
- **Describe a test the group doesn't have.** `context.descriptions.test` raises `Plugins::Error`.
- **Put description text in `plugins.yml`.** It only goes into the generated `<group>_group.rb` file.

## Reference

### plugin.yml

| Key | Required | Meaning |
|---|---|---|
| `id` | yes | snake_case, unique, the same as the key in the config |
| `name` | yes | a readable name |
| `version` | yes | the plugin's version |
| `entrypoint` | yes | the file to require, relative to the plugin's root |
| `class` | yes | the class to create |
| `description` | no | what the plugin generates |
| `host_version` | no | a version requirement, checked against `InfernoSuiteGenerator::VERSION` |
| `templates` | no | the templates folder, `templates` by default |
| `runtime` | no | the runtime folder, `runtime` by default |

### The context

| Field | What it holds |
|---|---|
| `manifest` | this plugin's `Manifest` |
| `options` | the `options` hash from the config entry, `{}` if none |
| `ig_resources` | `Generator::IGResources`, all loaded IG artifacts |
| `ig_metadata` | `Generator::IGMetadata`, the object the host writes to `metadata.yml` |
| `ig_demodata` | `Generator::IGDemodata`, the object the host writes to `demodata.yml` |
| `base_output_dir` | the generated suite folder |
| `config` | `Generator::GeneratorConfigKeeper`, the merged config |
| `metadata` | a writer for this plugin's `plugins.yml` sections |
| `descriptions` | a writer for Markdown added to group and test descriptions |

| Helper | What it does |
|---|---|
| `plugin_id` | the plugin's id |
| `groups` | the IG's groups minus those excluded by `skip` / `skip_generation` |
| `test_index(group)` | a `TestIndex` over the group's tests |
| `template_path(name)` | the path of a file in the plugin's templates folder |
| `runtime_output_dir` | where `install_runtime` puts the runtime files |
| `install_runtime` | copies the runtime folder into the generated suite |

### Find a group's tests

`TestIndex` finds a test by what it is, so a plugin doesn't have to rebuild the host's test ids:

```ruby
index = context.test_index(group)
index.find("read")                                     # => "au_core_v200_patient_read_test"
index.find("search", search_names: %w[patient code])   # parameter names in any order
index.find("include", include_targets: ["Patient"])
index.all("patch")                                     # every patch test, in group order

context.descriptions.test(group, index.find("read"), "Reads the patient used by later tests.")
```

`find` returns the first match or `nil`, and `all` returns every match. The kind is the host generator's template type (`TEMPLATE_TYPES` in [generator_constants.rb](../lib/inferno_suite_generator/utils/generator_constants.rb)), or the plugin id for a test a `TestGenerator` added.

| Kind | Details you can match on |
|---|---|
| `search`, `multiple_or_search`, `multiple_and_search`, `chain_search`, `provenance_revinclude_search` | `search_names` |
| `include` | `search_names`, `include_targets` |
| `patch`, `update` | `option`, the `test_id_option` from the config |

A test added without a kind, such as one from `configs.generic.register_generators`, is never found.

### TestGenerator

Set `template_name`, `class_name_suffix` and `test_id_suffix` on the subclass. The template is rendered against the generator, so it can call these public methods and any the subclass adds:

| Method | Example |
|---|---|
| `context`, `group_metadata`, `plugin_data`, `ig_metadata` | the inputs; `plugin_data` is this group's entry from the Extractor result |
| `suite_module_name` | `AUCoreTestKit` |
| `module_name` | `AUCoreV200` |
| `resource_type` | `Patient` |
| `profile_identifier` | `patient`, the group's folder name |
| `base_class_name`, `class_name` | `Patient`, `PatientReadTest` |
| `base_test_id`, `test_id` | `au_core_v200_patient` (also the group id), `au_core_v200_patient_read_test` |
| `output_file_directory`, `base_output_file_name`, `output_file_name` | where the test file is written |
| `insert_index(tests)` | the test's position in the group's test list, the end by default |

Inferno runs a group's tests in list order, and later tests reuse resources that earlier ones put in scratch. When `insert_index` runs, the list already holds every built-in test.

### plugins.yml

- `<suite dir>/plugins.yml` is written with `context.metadata.suite(data)`.
- `<suite dir>/<group dir>/plugins.yml` is written with `context.metadata.group(group, data)` or `.groups(data_by_group)`.

Each file is one hash whose top-level keys are plugin ids. Keys are written as strings.

```yaml
read:
  interaction:
    code: read
    expectation: SHALL
  tests:
  - id: au_core_v200_patient_read_test
    file_name: patient_read_test.rb
another_plugin:
  any: data
```

### Description text

- The group template puts the text inside a `%( ... )` literal, so the host escapes `\`, `(`, `)`, `#{`, `#@` and `#$` for you.
- Texts from several plugins come in config order, and each plugin's texts in the order it added them.
- Any `GroupMetadata` for a profile reaches the same group, because entries are keyed by the group's folder name.

## Where to look in the code

| File | What it does |
|---|---|
| [lib/inferno_suite_generator.rb](../lib/inferno_suite_generator.rb) | The host's run: `load_plugins`, then `run_plugins` after the built-in tests |
| [plugins/loader.rb](../lib/inferno_suite_generator/plugins/loader.rb) | Step 1: reads the config and finds each plugin |
| [plugins/manifest.rb](../lib/inferno_suite_generator/plugins/manifest.rb) | Step 1: reads and checks `plugin.yml` |
| [plugins/loaded_plugin.rb](../lib/inferno_suite_generator/plugins/loaded_plugin.rb) | Step 1: creates the plugin class; Step 2: builds its context |
| [plugins/runner.rb](../lib/inferno_suite_generator/plugins/runner.rb) | Step 2: runs the plugins in order, then writes `plugins.yml` |
| [plugins/context.rb](../lib/inferno_suite_generator/plugins/context.rb) | Step 2: what a plugin gets, plus its helpers |
| [plugins/test_index.rb](../lib/inferno_suite_generator/plugins/test_index.rb) | Step 2: finds a group's tests by kind |
| [plugins/metadata_store.rb](../lib/inferno_suite_generator/plugins/metadata_store.rb) | Step 3: collects and writes `plugins.yml` |
| [plugins/test_generator.rb](../lib/inferno_suite_generator/plugins/test_generator.rb) | Step 3: renders a test per group and adds it to the group |
| [plugins/group_descriptions.rb](../lib/inferno_suite_generator/plugins/group_descriptions.rb) | Step 3: collects and escapes description text |
| [generators/group_generator.rb](../lib/inferno_suite_generator/generators/group_generator.rb) | Step 4: adds the plugins' text to group and test descriptions |
| [plugins/extractor.rb](../lib/inferno_suite_generator/plugins/extractor.rb) | A base class for per-group data |
| [plugins/runtime_metadata.rb](../lib/inferno_suite_generator/plugins/runtime_metadata.rb) | Reads `plugins.yml` from a generated test |
| [plugins/scaffold.rb](../lib/inferno_suite_generator/plugins/scaffold.rb) | Creates a new plugin folder |
| [plugins/testing.rb](../lib/inferno_suite_generator/plugins/testing.rb) | Helpers for plugin tests |
