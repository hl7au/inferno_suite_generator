# Questionnaire usage tracing plugin

Traces which SDC questionnaires in the IG use each profile in the suite, and adds a "Used in questionnaires" section to the description of every group a questionnaire uses. Testers see which form items depend on the resources a group tests and which elements those items read.

## Enable it

It ships with the generator. Add it to the generator config:

```json
"plugins": {
  "questionnaire_usage_tracing": { "builtin": "questionnaire_usage_tracing" }
}
```

It has no options.

## What it traces

Every `Questionnaire` in the IG package, in three kinds of sources:

- **Queries**: `x-fhir-query` variables, such as `Observation?code=8302-2&patient={{%patient.id}}`, including resources they fetch with `_include`
- **Launch contexts**: `sdc-questionnaire-launchContext` resources, such as `%patient`
- **Template extracts**: contained resources used by `templateExtract`

Each source is matched to the suite's groups by resource type and by the `code` and `category` the profiles fix. Then the plugin collects the items that use the source through any FHIRPath expression in their extensions, such as `initialExpression`, `calculatedExpression` or a variable, and the element paths those expressions read.

Sources it can't match to a group are logged as `Questionnaire usage tracing: ...` and left out.

## What it generates

For each group a questionnaire uses:

- An `entries` list under `questionnaire_usage_tracing` in `<group dir>/plugins.yml`, with one entry per source:

```yaml
questionnaire_usage_tracing:
  entries:
  - source: launch_context
    questionnaire_url: http://example.org/Questionnaire/form
    questionnaire_version: 0.1.0
    questionnaire_title: Example form
    name: patient
    elements_read:
    - birthDate
    used_in:
    - link_id: dob
      text: Date of birth
      extension: initialExpression
      reads:
      - birthDate
```

- A "Used in questionnaires" section at the end of the group description. It's a nested list of questionnaires, the sources in each that use the profile and the items that use each source. Elements the profile neither marks Must Support nor requires are marked "(not checked)".

Groups no questionnaire uses get no `plugins.yml` entry, and their descriptions don't change.

## Layout

- `lib/questionnaire_usage_tracing/plugin.rb`: `generate(context)`, which traces the IG and writes the results
- `lib/questionnaire_usage_tracing/tracer.rb`: finds the sources in each questionnaire and the items that use them
- `lib/questionnaire_usage_tracing/ast.rb`: reads FHIRPath expressions to find the variables and element paths they use
- `lib/questionnaire_usage_tracing/profile_matcher.rb`: matches a source to the groups whose profile it fits
- `lib/questionnaire_usage_tracing/query_search.rb`: splits a FHIR query into its resource type and search parameters
- `lib/questionnaire_usage_tracing/usage_section.rb`: renders the "Used in questionnaires" Markdown
- `test/`: unit tests for each class, plus `plugin_test.rb`, which runs the plugin the way the host does

## Test

```bash
bundle exec rake test
bundle exec ruby -Ilib plugins/questionnaire_usage_tracing/test/plugin_test.rb
```
