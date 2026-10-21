# read plugin: notes for agents

This folder is an inferno_suite_generator plugin. Keep every change inside it unless the task is about the plugin framework in `lib/inferno_suite_generator/plugins/`.

## Contract

- `plugin.yml` is the source of truth for the id, version, entrypoint and class. Bump `version` when the generated output changes.
- `InfernoSuitePlugins::Read::Plugin#generate(context)` is the only entry point. `context` is an `InfernoSuiteGenerator::Plugins::Context`.
- Write plugin data only through `context.metadata`. It ends up under `read` in each group's `plugins.yml`.
- Never edit the host's `metadata.yml` or `demodata.yml`.

## Keep the built-in parity

Until the built-in `ReadTestGenerator` is removed, this plugin must produce the same tests apart from its runtime module and the `plugin_metadata` accessor: same class names, test ids, file names, test body and place in the group. `test/read_plugin_test.rb` checks this. If you change `templates/read.rb.erb` on purpose, update the parity test in the same change and say why.

`runtime/read_test.rb` runs inside Inferno, not in the generator. It is copied into each generated suite, so it may only depend on Inferno, fhir_models and the gem's `InfernoSuiteGenerator::BasicTest`.

## Check your work

```bash
bundle exec ruby -Ilib plugins/read/test/read_plugin_test.rb
bundle exec ruby -Ilib plugins/read/test/runtime_read_test_test.rb
bundle exec rubocop plugins/read
bundle exec reek plugins/read
```
