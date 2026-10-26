# profile_read plugin: notes for agents

This folder is a plugin that ships with inferno_suite_generator. Keep every change inside it unless the task is about the plugin framework in `lib/inferno_suite_generator/plugins/`. It is independent of the host's built-in read tests: don't reuse `ReadTestGenerator`, `read.rb.erb` or `test_modules/read_test.rb` from the host.

## Contract

- `plugin.yml` is the source of truth for the id, version, entrypoint and class. Bump `version` when the generated output changes.
- `InfernoSuitePlugins::ProfileRead::Plugin#generate(context)` is the only entry point. `context` is an `InfernoSuiteGenerator::Plugins::Context`.
- Write plugin data only through `context.metadata`. It ends up under `profile_read` in each group's `plugins.yml`.
- Never edit the host's `metadata.yml` or `demodata.yml`.

## Where things go

- `lib/profile_read/extractor.rb`: each group's read data, written to `plugins.yml` and passed to the test generator
- `lib/profile_read/read_test_generator.rb` and `templates/profile_read.rb.erb`: the generated test file
- `runtime/profile_read_test.rb`: what the test does in Inferno. It is copied into the suite, so it may only use Inferno, `fhir_models` and the data in `plugins.yml`. It must not require anything from `lib/`.

## Check your work

```bash
bundle exec rake test
bundle exec rubocop plugins/profile_read
bundle exec reek plugins/profile_read
```
