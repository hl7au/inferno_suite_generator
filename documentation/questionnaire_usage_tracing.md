# Questionnaire usage tracing: which questionnaire items depend on each generated test

Source files:

- [lib/inferno_suite_generator.rb](../lib/inferno_suite_generator.rb) (Generator#generate_questionnaire_usage, Generator#generate_groups)
- [lib/inferno_suite_generator/questionnaire_usage.rb](../lib/inferno_suite_generator/questionnaire_usage.rb) (QuestionnaireUsage.descriptions, the entry point)
- [lib/inferno_suite_generator/questionnaire_usage/](../lib/inferno_suite_generator/questionnaire_usage/) (sources, FHIRPath chains, code matching, Markdown)
- [lib/inferno_suite_generator/core/group_metadata.rb](../lib/inferno_suite_generator/core/group_metadata.rb) (GroupMetadata#add_test, #test_kind, #find_test)
- [lib/inferno_suite_generator/generators/group_generator.rb](../lib/inferno_suite_generator/generators/group_generator.rb) (GroupGenerator, which writes the added text)
- [lib/inferno_suite_generator/core/config/getters.rb](../lib/inferno_suite_generator/core/config/getters.rb) (questionnaire_usage_tracing?)

---

## 1. What

Many IGs publish SDC `Questionnaire` resources that read from the FHIR server to pre-fill answers and write back to it on extraction. A server can pass a read test and still break such a form, because an item reads an element the profile neither marks Must Support nor requires, so no test checks it.

With tracing on, the generator adds a **Used in questionnaires** section to the descriptions it already writes:

- each test that makes the same request a questionnaire makes lists the forms, their sources and the items that use them, with the element paths each item reads
- the Must Support test lists the elements items read that the group's tests check
- the group description summarizes which tests cover each form, the requests no test makes and the elements no test checks

Tracing only documents coverage. It adds no tests and changes nothing a test checks.

## 2. How to enable it

Add the flag to the `configs.generic` section of the kit's config:

```json
{
  "configs": {
    "generic": {
      "questionnaire_usage_tracing": true
    }
  }
}
```

Only the JSON boolean `true` turns it on. A missing key or any other value (`"true"`, `1`) leaves it off.

- With the flag off, the generated kit is byte-identical to a kit generated without this feature.
- With the flag on and no `Questionnaire` in the IG, the kit is also unchanged.
- `metadata.yml` and `demodata.yml` never change.

## 3. Where it runs

```ruby
def generate_questionnaire_usage
  config = Registry.get(:config_keeper)
  return unless config.questionnaire_usage_tracing?

  groups = ig_metadata.ordered_groups.compact.reject do |group|
    config.exclude_resource?(group.profile_url, group.resource)
  end
  self.questionnaire_usage = QuestionnaireUsage.descriptions(ig_resources:, groups:)
end
```

`Generator#generate` calls it after every test generator (read through patch) and before `generate_groups`, because tracing looks up the tests the generators recorded. Groups excluded with `skip_generation` (or `skip`) are not traced. `generate_groups` passes the result, or `{}` when tracing is off, as the third argument of `GroupGenerator.generate`.

`QuestionnaireUsage.descriptions` writes no files and changes no groups. It returns `{ group_metadata => { "test_id" | :group => markdown } }`, and `GroupGenerator` is the only place that writes the text into the group file.

## 4. What it traces

Every `Questionnaire` in the IG. A form's sources are, in document order:

1. **Queries**: each `variable` extension with language `application/x-fhir-query`, on the root or on any item. A query is a read when an id follows the resource type (`Patient/{{%patient.id}}`), otherwise a search. Its search parameters are the names without modifiers; a compartment search adds the compartment (`patient`); result-shaping parameters such as `_sort`, `_count` and `_include` are not search parameters.
2. **Includes**: each `_include=<Type>:<param>[:<Target>]` of a query, one source per target type. Without an explicit target, the target comes from the IG `SearchParameter`, else from the types the form's own FHIRPath picks out of the query's results.
3. **Launch contexts**: each root `sdc-questionnaire-launchContext`, one source per `type`.
4. **Templates**: each `sdc-questionnaire-templateExtract` whose `template` reference names a contained resource. A template with a `…/TemplateExtractExtensionPatchRequestUrl` sub-extension is a FHIRPath Patch; any other creates a resource.

An **item use** is a `text/fhirpath` expression on the root or an item that reads a source's `%name`, directly or through FHIRPath variables. The element paths it reads are relative to the resource (`name.family`, `value.value`); on a search Bundle only chains through `entry` … `resource` read elements.

Sources are matched to groups by resource type. A search query or a create template is also matched by the `code` and `category` the profiles fix, so a vital-signs query goes to the profile whose code it asks for.

Anything the tracer cannot handle (a FHIRPath expression that does not parse, an `_include:iterate`, a template with no contained resource, a source with no matching group) is logged to stdout with the prefix `Questionnaire usage tracing: ` and skipped; generation goes on.

## 5. Which test lists a source

A source is shown when an item uses it, when it is a template, or when it is a query with its own `_include`. For each group the source fits, the first test found in this order lists it:

| Source | Tests tried, in order |
|---|---|
| Launch context, or a read query | the group's `read` test |
| Search query | the group's `search` test with the same `search_names`, in any order. A query with no search parameters has no test. |
| Include | for each group of the query's type: its `include` test with the query's `search_names` and `include_targets` equal to this group's resource, then its `include` test with those `include_targets` |
| Create template | the group's `create` test |
| Patch template | the group's `patch` test, then its `update` test recorded with `option: "update"`. An update test that creates the resource is never used. |

A source with no such test appears in the group summary under **Not tested by this group**.

Tests are found only through `GroupMetadata#find_test(kind, **details)`, which reads the kind and details each generator records with `add_test`. Custom generators that subclass the built-in ones inherit the recording and can override `test_details` to add details.

An element path is **checked** when the group's profile marks it Must Support, requires it, or it is `id` or part of a Must Support extension slice. Unchecked paths are marked `(not checked)` in item lines and listed under **Elements not checked** in the summary.

## 6. What it generates

For a Patient group with read and Must Support tests, `name.family` Must Support, and a form whose launch context `patient` pre-fills two items, the read test gets:

```markdown
**Used in questionnaires**

These questionnaires in the IG read Patient resources as this test does: by id, or as the resource a form is opened for. A form can pre-fill an item only if the server returns the elements the item reads. Elements marked (not checked) are neither Must Support nor required by the profile, so this group's tests do not check them.

- **Demo form**
  - **Launch context patient**: the Patient the form is opened for
    - **Family name**: pre-fills the answer; reads name.family
    - **Marital status**: pre-fills the answer; reads maritalStatus (not checked)
```

the Must Support test gets:

```markdown
**Used in questionnaires**

Items in these questionnaires read elements of Patient that this group's tests check. A form can pre-fill an item only if the server returns the elements the item reads.

- **Demo form**
  - **name.family**: Family name
```

and the group description gets:

```markdown
**Used in questionnaires**

These questionnaires in the IG read or create Patient Profile resources. The tests that make the same requests list the form items that depend on them.

- **Demo form**: see the read and Must Support tests

**Elements not checked**

The profile neither marks these elements Must Support nor requires them, so no test checks that the server returns them.

- **Demo form**
  - **maritalStatus**: Marital status
```

Inferno shows tables without borders and raw HTML as text, so the sections use only nested lists, bold and plain text. Item lines are capped at 25 per source and Must Support item labels at 10 per element.

In the group file, the group text is appended to the built-in description. A test with added text is emitted as

```ruby
test from: :<id> do
  description [description, %(
<text>
  )].compact.map(&:strip).join("\n\n")
end
```

so the text follows the test's own description. Tests without added text keep their plain `test from: :<id>` line. `GroupGenerator` escapes `\`, `(`, `)`, `#{`, `#@` and `#$` so the file compiles whatever the questionnaire text contains.

## 7. How to run the tests

The tests build small in-memory questionnaires and groups and call the public entry points: `QuestionnaireUsage.descriptions`, `GroupMetadata`, `GroupGenerator.generate` and `Generator#generate_questionnaire_usage`.

```sh
bundle exec rake test                  # whole suite
bundle exec ruby -Ilib -Itest test/questionnaire_usage_query_test.rb   # one file
bundle exec rake                       # RuboCop
bundle exec reek .                     # Reek
```

Pass `.` to reek: without a path it reads source from stdin when stdin is not a terminal, as in CI or an editor task.

| Test file | Covers |
|---|---|
| `test/generator_questionnaire_usage_test.rb` | the flag, excluded groups, pipeline order |
| `test/generator_config_keeper_test.rb` | the flag getter, one config per keeper |
| `test/generator_test_kinds_test.rb`, `test/group_metadata_find_test_test.rb` | kind recording and `find_test` |
| `test/group_generator_descriptions_test.rb` | writing and escaping the text in the group file |
| `test/questionnaire_usage_launch_context_test.rb`, `test/questionnaire_usage_labels_test.rb` | launch contexts, read and Must Support sections, summary, labels, caps |
| `test/questionnaire_usage_fhirpath_test.rb` | variables, filter arguments, extension reads |
| `test/questionnaire_usage_query*_test.rb` | queries, Bundle chains, code matching, search and read picking |
| `test/questionnaire_usage_include*_test.rb` | `_include` sources and include test picking |
| `test/questionnaire_usage_template*_test.rb` | templates and create, patch and update picking |
