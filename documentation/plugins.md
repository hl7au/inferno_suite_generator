# Plugins: custom generators that run inside the host generator

Source files:

- [lib/inferno_suite_generator/plugins/](../lib/inferno_suite_generator/plugins/) (the plugin framework)
- [lib/inferno_suite_generator.rb](../lib/inferno_suite_generator.rb) (Generator#load_plugins, #run_plugins)

---

## 1. What

A plugin is a gem or a folder that generates extra tests, or extra data, during a generator run. It gets everything the host has built: the IG resources, the extracted metadata and demo data, the output directory and the merged config.

Every plugin has:

- a `plugin.yml` manifest at its root, with its id, version, entrypoint and class
- a class with a `generate(context)` method, the plugin contract

A plugin can also have its own extractors, ERB templates, test generators, runtime code for the generated tests, tests, docs and agent notes. All of it lives in the plugin's folder.

The host keeps its own files as they are. Plugin data goes into separate `plugins.yml` files, keyed by plugin id.

## 2. Why

- Teams can add IG-specific tests without forking the generator.
- Each test type can move into its own isolated plugin, with its own tests and docs, one at a time.
- The host's `metadata.yml` and `demodata.yml` stay unchanged, so nothing that reads them breaks.

`configs.generic.register_generators` still works. Plugins are the structured replacement: they carry a manifest, a version and a contract, and can bring their own data and runtime files.

## 3. How

### Step 0: Enable a plugin

Add a top-level `plugins` section to any config file. It is keyed by plugin id, which must match the id in the plugin's `plugin.yml`. Each entry names exactly one source:

```json
"plugins": {
  "local":  { "path": "plugins/local", "options": { "any": "value" } },
  "shared": { "gem": "isg_shared_plugin" },
  "off":    { "path": "plugins/off", "enabled": false }
}
```

| Source | Resolves to |
|---|---|
| builtin | plugins/<name> inside this gem |
| path | a folder, relative to the working directory |
| gem | the root of an installed gem (its gemspec must ship plugin.yml) |

`options` is passed to the plugin as `context.options`. Plugins run in config order. Because the section is keyed by id, a later config file can override one plugin's entry, for example to set `"enabled": false`.

### Step 1: The manifest

```yaml
id: read                                  # snake_case, unique
name: Read tests
version: 0.1.0
description: Generates a read interaction test for every profile that declares read
entrypoint: lib/read.rb                   # required before the plugin runs, relative to the root
class: InfernoSuitePlugins::Read::Plugin  # created with no arguments
host_version: ">= 0.1.0"                  # optional, checked against InfernoSuiteGenerator::VERSION
templates: templates                      # optional, default "templates"
runtime: runtime                          # optional, default "runtime"
```

Put plugin code under `InfernoSuitePlugins::<CamelCaseId>`. All plugins load into one Ruby process, so this keeps their constants apart from each other and from the host.

### Step 2: When plugins run

```
load_plugins            # manifests validated, entrypoints required, before the IG is loaded
load_ig_package
extract_metadata
extract_demodata
built-in tests
run_plugins             # every enabled plugin, in config order
generate_groups         # each group's description gets the text plugins added to it
generate_suites
```

1. Generator#load_plugins reads the `plugins` section and loads every enabled plugin. A bad manifest, a missing class or a `generate` that takes no argument stops the run before any IG work starts.
2. The host generates its built-in tests.
3. Generator#run_plugins runs the plugins in config order, then writes all `plugins.yml` files.
4. Groups and suites are generated last, so every test a plugin registers appears in its group. Generator#generate_groups also appends the Markdown each plugin added for a group to that group's description (Step 6).

Inferno runs a group's tests in the order of the group's test list, and later tests reuse resources that earlier ones put in scratch. A plugin test goes at the end of the list unless its TestGenerator overrides `insert_index` (Step 4).

### Step 3: The context

`generate(context)` receives a `Plugins::Context`:

| Field | Content |
|---|---|
| manifest | this plugin's Manifest |
| options | the options hash from the config entry, {} if none |
| ig_resources | Generator::IGResources, all loaded IG artifacts |
| ig_metadata | Generator::IGMetadata, the object the host writes to metadata.yml |
| ig_demodata | Generator::IGDemodata, the object the host writes to demodata.yml |
| base_output_dir | the generated suite directory |
| config | Generator::GeneratorConfigKeeper, the merged config |
| metadata | a writer for this plugin's plugins.yml sections |
| descriptions | a writer for Markdown appended to group descriptions |

Helpers:

- `context.groups`: the IG groups minus those excluded by `skip` / `skip_generation`
- `context.template_path(name)`: a file in the plugin's templates directory
- `context.install_runtime`: copies the plugin's `runtime/` folder to `<suite dir>/plugins/<id>/`, so tests generated from a folder plugin can `require_relative '../plugins/<id>/<file>'` without the plugin being installed where Inferno runs

### Step 4: Tooling for plugin code

| Class | Use it for |
|---|---|
| Plugins::Base | the contract; inheriting from it is optional |
| Plugins::Extractor | per-group data extraction: implement `extract` and return a hash, or nil to skip the group. `MyExtractor.extract(context)` returns `{ group_metadata => data }` |
| Plugins::TestGenerator | one test file per group from an ERB template. Set `template_name`, `class_name_suffix` and `test_id_suffix`, and override `insert_index` to choose the test's place in the group |
| Plugins::RuntimeMetadata | reading the plugin's plugins.yml section from a generated test at Inferno run time |
| Plugins::GroupDescriptions | collecting the Markdown plugins add to group descriptions; `run_plugin` returns it in tests |
| Plugins::Testing | plugin tests: build group and IG metadata, run the plugin into a temporary directory, read plugins.yml |
| Plugins::Scaffold | creating a new plugin folder |

Plugins::TestGenerator does not depend on the host's own generator classes. Templates and subclasses can call its public methods:

| Method | Example |
|---|---|
| context, group_metadata, plugin_data, ig_metadata | the inputs; plugin_data is this group's entry from the Extractor result |
| suite_module_name | AUCoreTestKit |
| module_name | AUCoreV200 |
| resource_type | Patient |
| profile_identifier | patient, the group's directory name |
| base_class_name, class_name | Patient, PatientReadTest |
| base_test_id, test_id | au_core_v200_patient (also the group id), au_core_v200_patient_read_test |
| output_file_directory, base_output_file_name, output_file_name | where the test file is written |
| insert_index(tests) | the test's position in the group's test list; the end by default |

`TestGenerator#generate` writes the file and inserts `{ id:, file_name: }` into the group's test list at `insert_index`, so the group requires and runs it. When `insert_index` runs, the list already holds every built-in test. `generate` also appends the same entry to `tests` in the plugin's section of the group's `plugins.yml`. If the group already has a test with the same id, from the host or another plugin, it raises Plugins::Error instead.

A complete plugin, for example one that adds a read test to every group with a read interaction, in four steps:

```ruby
module InfernoSuitePlugins
  module Read
    class Plugin < InfernoSuiteGenerator::Plugins::Base
      def generate(context)
        data_by_group = Extractor.extract(context)       # this plugin's data for each group with a read interaction
        context.metadata.groups(data_by_group)           # stored under "read" in each group's plugins.yml
        TestGenerator.generate(context, data_by_group)   # one read test per group, added to the group
        context.install_runtime                          # runtime/read_test.rb, which the read tests include
      end
    end
  end
end
```

### Step 5: plugins.yml

The host writes `metadata.yml` and `demodata.yml` as before, and plugins never touch them. Plugin data goes to `plugins.yml` files:

- `<suite dir>/plugins.yml`, written with `context.metadata.suite(data)`
- `<suite dir>/<group dir>/plugins.yml`, next to the group's `metadata.yml`, written with `context.metadata.group(group_metadata, data)` or `context.metadata.groups(data_by_group)`

Each file is one hash whose top-level keys are plugin ids:

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

Keys are written as strings. When a plugin writes to the same file more than once, nested hashes merge, arrays are appended to and other values are replaced. The files are written once, after the last plugin has run.

A generated test reads its section back at run time:

```ruby
def self.plugin_metadata
  @plugin_metadata ||= InfernoSuiteGenerator::Plugins::RuntimeMetadata.load(__dir__, "read")
end
```

### Step 6: Group descriptions

A plugin can add Markdown to the description of any group it generates tests for:

```ruby
usage_by_group = UsageExtractor.extract(context)                    # { group_metadata => markdown }
context.descriptions.groups(usage_by_group)                         # one text per group
context.descriptions.group(context.groups.first, "## Usage\n\n...") # or one group at a time
```

- Pass plain Markdown. The group template puts the description inside a `%( ... )` literal, so the host escapes `\`, `(`, `)`, `#{`, `#@` and `#$` for you. Nil or blank text is ignored.
- The text is appended after the built-in description, separated by a blank line. Texts from several plugins come in config order, and each plugin's texts in the order it added them.
- Plugins can only append. They can't change, remove or reorder the built-in sections.
- Any GroupMetadata for a profile reaches the same group: entries are keyed by the group's directory name.
- The text goes only into the generated `<group>_group.rb` file. It isn't written to `plugins.yml`.
- A group that gets no plugin text keeps exactly the description it had before.

In plugin tests, `run_plugin` returns the collected Plugins::GroupDescriptions:

```ruby
descriptions = run_plugin(PLUGIN_ROOT, ig_metadata: build_ig_metadata(groups: [group]), base_output_dir: dir)
descriptions.for(group) # => ["## Usage\n\n..."]
```

### Step 7: Create and test a plugin

```bash
bundle exec rake 'plugins:new[my_plugin]'                  # creates plugins/my_plugin
bundle exec rake 'plugins:new[my_plugin,path/to/my_plugin]'
```

Outside this repository, `require "inferno_suite_generator/plugins/scaffold"` and call `InfernoSuiteGenerator::Plugins::Scaffold.new(id: "my_plugin", destination: "plugins/my_plugin").create`.

The skeleton has `plugin.yml`, an entrypoint, a Plugin class, an Extractor, a test, a README and an AGENTS.md with instructions for coding agents. It runs as it is: it writes each group's resource type and profile URL to `plugins.yml`.

Plugin tests use Plugins::Testing:

```ruby
include InfernoSuiteGenerator::Plugins::Testing

group = build_group_metadata(interactions: [{ code: "read", expectation: "SHALL" }])
run_plugin(PLUGIN_ROOT, ig_metadata: build_ig_metadata(groups: [group]), base_output_dir: dir)
plugin_metadata(File.join(dir, "patient"), "my_plugin") # => { "resource" => "Patient", ... }
```

`run_plugin` loads the plugin through the real Loader. It registers a GeneratorConfigKeeper for the run (pass `config:` to set config values) and writes the `plugins.yml` files. In this repository, `bundle exec rake test` also runs `plugins/*/test/**/*_test.rb`. Plugin tests are left out of the packaged gem.

### Step 8: Ship a plugin as a gem

Put `plugin.yml` at the gem root and include it, the templates and the runtime files in `spec.files`. Users then enable it with `{ "gem": "<gem name>" }`. Depend on `inferno_suite_generator` in the gemspec, and set `host_version` in `plugin.yml` to the range you test against.
