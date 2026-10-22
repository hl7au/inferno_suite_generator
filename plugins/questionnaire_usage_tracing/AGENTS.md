# questionnaire_usage_tracing plugin: notes for agents

This folder is a plugin that ships with inferno_suite_generator. Keep every change inside it unless the task is about the plugin framework in `lib/inferno_suite_generator/plugins/`.

## Contract

- `plugin.yml` is the source of truth for the id, version, entrypoint and class. Bump `version` when the generated output changes.
- `InfernoSuitePlugins::QuestionnaireUsageTracing::Plugin#generate(context)` is the only entry point. `context` is an `InfernoSuiteGenerator::Plugins::Context`.
- Write plugin data only through `context.metadata`. It ends up under `questionnaire_usage_tracing` in each group's `plugins.yml`.
- Add text to a group's description only through `context.descriptions`, with plain Markdown. The host escapes it for the group template, so don't escape it here.
- Never edit the host's `metadata.yml` or `demodata.yml`.

## Markdown

Inferno shows tables without borders and raw HTML as text. Keep the section to nested lists, bold and plain text.

## Check your work

```bash
bundle exec rake test
bundle exec rubocop plugins/questionnaire_usage_tracing
```
