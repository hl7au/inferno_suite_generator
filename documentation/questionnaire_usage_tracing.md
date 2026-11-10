# Questionnaire usage tracing

Traces which SDC questionnaires in the IG use each profile in the suite, and adds a "Used in questionnaires" section to the tests that make the same requests and to the group. Testers see, next to each test, which form items depend on what it checks and which elements those items read.

## Enable it

Tracing is off by default. A kit turns it on in the generator config:

```json
"configs": {
  "generic": {
    "questionnaire_usage_tracing": true
  }
}
```

Without the flag, the generated suite doesn't change. With it, an IG that has no `Questionnaire` resources doesn't change either.

## What it traces

Every `Questionnaire` in the IG package, in three kinds of sources:

- **Queries**: `x-fhir-query` variables, such as `Observation?code=8302-2&patient={{%patient.id}}`, including resources they fetch with `_include`
- **Launch contexts**: `sdc-questionnaire-launchContext` resources, such as `%patient`
- **Template extracts**: contained resources used by `templateExtract`

Each source is matched to the suite's groups by resource type and by the `code` and `category` the profiles fix. Then the generator collects the items that use the source through any FHIRPath expression in their extensions, such as `initialExpression`, `calculatedExpression` or a variable, and the element paths those expressions read.

Sources it can't match to a group are logged as `Questionnaire usage tracing: ...` and left out.

## What it generates

For each group a questionnaire uses, the trace is split over the group's tests. Each source goes to the test that makes its request:

| Source | Test |
|---|---|
| Launch context, or a query that reads one resource by id | the read test |
| Search query | the search test by the same parameters, in any order |
| `_include` | the include test for this type in the group of the query's own type, preferably the one that searches by the query's parameters |
| Template extract | the create test, or for a FHIRPath Patch the patch test, then the update test |

The generator finds these tests through `Generator::TestIndex`. It writes:

- A "Used in questionnaires" section in the description of each of those tests. It's a nested list of questionnaires, the sources in each that the test makes the request of, and the items that use each source. Elements that no group the entry links to marks Must Support or requires are marked "(not checked)".
- A section in the Must Support test listing the Must Support elements the items read, each with the items that read it.
- A "Used in questionnaires" section at the end of the group description, with:
  - each questionnaire and the tests that list it
  - **Not tested by this group**: the sources no test makes the request of, in full, with how the group's searches compare to a query's
  - **Elements not checked**: the elements items read that no group the entry links to marks Must Support or requires, each with the items that read it
- An `entries` list in `<group dir>/questionnaire_usage.yml`, with one entry per source. `tested_by` lists the ids of the tests whose descriptions list the entry:

```yaml
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
  tested_by:
  - au_core_v200_patient_read_test
  - au_core_v200_patient_must_support_test
```

`used_in` also records the variables items define, which sections leave out: they list the items that read the variable.

Groups no questionnaire uses get no `questionnaire_usage.yml`, and their descriptions and their tests' descriptions don't change.

## How it runs

`QuestionnaireUsage.generate` runs these steps in order. In the diagrams here, a dotted line attaches a note to a step.

```mermaid
flowchart TD
    n0@{ shape: brace, label: "Runs when a kit opts in" }
    n1(["Start tracing"])
    n2{"No recorded tests?"}
    n3(["Stop with an error"])
    n4>"Trace sources"]
    n5>"Decide delivery"]
    n6>"Write sections"]
    n7@{ shape: doc, label: "Write trace files" }
    n8(["Done"])
    n0 -.- n1
    n1 --> n2
    n2 -->|"yes"| n3
    n2 -->|"no"| n4
    n4 --> n5
    n5 --> n6
    n6 --> n7
    n7 --> n8
```

### Trace each questionnaire

`Tracer#trace` returns `{ profile_url => [TraceEntry] }`. A source that matches no group gets no entry.

```mermaid
flowchart TD
    n0>"Overview"]
    n1["Start an empty trace"]
    n2(("Next form"))
    n3{"Questionnaire left?"}
    n4["Read the form"]
    n5@{ shape: curv-trap, label: "Warn about module forms" }
    n6[["Trace queries and includes"]]
    n7[["Trace launch contexts"]]
    n8[["Trace extraction templates"]]
    n9(["Return traces by profile"])
    n10@{ shape: brace, label: "Links a source to groups" }
    n11@{ shape: brace, label: "Finds the items reading it" }
    n0 --> n1
    n1 --> n2
    n2 --> n3
    n3 -->|"yes"| n4
    n3 -->|"no"| n9
    n4 --> n5
    n5 --> n6
    n6 --> n7
    n7 --> n8
    n8 --> n2
    n10 -.- n6
    n11 -.- n7
```

### Decide which tests list each entry

`Delivery.new` makes these decisions. "Pick Must Support reads", "Find the request test" and "Record the placement" run for each entry of the group, and only a shown entry gets a request test. [How it picks a test](#how-it-picks-a-test) has the rules.

```mermaid
flowchart TD
    n0>"Overview"]
    n1["Prepare the test lookup"]
    n2["Find each entry's groups"]
    n3["Decide checked, once per entry"]
    n4(("Next group"))
    n5{"Traced group left?"}
    n6["Load the group's own rules"]
    n7["Pick Must Support reads"]
    n8[["Find the request test"]]
    n9["Record the placement"]
    n10(["Delivery is ready"])
    n11@{ shape: brace, label: "Any group's check counts" }
    n12@{ shape: brace, label: "Each kind picks its lookup" }
    n13@{ shape: brace, label: "Outputs ask by test too" }
    n0 --> n1
    n1 --> n2
    n2 --> n3
    n3 --> n4
    n4 --> n5
    n5 -->|"yes"| n6
    n5 -->|"no"| n10
    n6 --> n7
    n7 --> n8
    n8 --> n9
    n9 --> n4
    n11 -.- n3
    n12 -.- n8
    n13 -.- n10
```

### Write the "Used in questionnaires" sections

`Sections#write` only collects the text in `Generator::GroupDescriptions`. `GroupGenerator` writes it to the group files later.

```mermaid
flowchart TD
    n0>"Overview"]
    n1(("Next group"))
    n2{"Traced group left?"}
    n3["Add Must Support section"]
    n4["Add group summary"]
    n5(("Next test"))
    n6{"Request test left?"}
    n7["Add test section"]
    n8(["Text is collected"])
    n9@{ shape: brace, label: "Says what no test covers" }
    n10@{ shape: brace, label: "Intro depends on test kind" }
    n11@{ shape: brace, label: "Reaches group files later" }
    n0 --> n1
    n1 --> n2
    n2 -->|"yes"| n3
    n2 -->|"no"| n5
    n3 --> n4
    n4 --> n1
    n5 --> n6
    n6 -->|"yes"| n7
    n6 -->|"no"| n8
    n7 --> n5
    n9 -.- n4
    n10 -.- n7
    n11 -.- n8
```

## How it picks a test

Each trace entry of a group takes two paths: its request goes to one test (`Delivery#request_test`, through the entry's `TraceEntry#request_lookups`), and the elements its items read go to the Must Support test or the group summary (`Delivery::Placement#reads`). `Delivery` makes these decisions once, before anything is rendered, and the test sections, the group summaries and the trace files all read them.

### The request

```mermaid
flowchart TD
    entry["Trace entry of group G"] --> shown{"Shown?<br/>an item uses it beyond a variable,<br/>or it is a template,<br/>or a query with its own _include"}
    shown -- no --> yml["questionnaire_usage.yml only<br/>tested_by: []"]
    shown -- yes --> source{"source"}

    source -- launch_context --> read["G's read test"]
    source -- query --> isread{"read: true?<br/>like Patient/id"}
    isread -- yes --> read
    isread -- no --> params{"FhirQuery#search_params<br/>empty?"}
    params -- yes --> none
    params -- no --> search["G's search test with the<br/>same names, in any order"]

    source -- include --> base["groups B of the query's own type,<br/>e.g. PractitionerRole"]
    base --> exact["B's include test with<br/>include_targets = G.resource and<br/>search_names = query params"]
    exact -- not found --> anyinc["B's include test with<br/>include_targets = G.resource"]

    source -- template_extract --> patch{"patch?"}
    patch -- no --> create["G's create test"]
    patch -- yes --> patchtest["G's patch test"]
    patchtest -- not found --> update["G's update test"]

    read -- found --> section["Used in questionnaires<br/>section in that test"]
    search -- found --> section
    exact -- found --> section
    anyinc -- found --> section
    create -- found --> section
    patchtest -- found --> section
    update -- found --> section

    read -- not found --> none["Group summary:<br/>Not tested by this group"]
    search -- not found --> none
    anyinc -- not found --> none
    create -- not found --> none
    update -- not found --> none
```

An include test belongs to group B, so it lists entries traced for group G. An `_include` links to every group of its target type, so the test lists the entry once, and an element counts as checked when any of those groups checks it. All lookups go through `Generator::TestIndex`, which finds tests by the kind and details the generators recorded. Those exist only in memory, so `Generator#generate` runs the tracing after the test generators and before `GroupGenerator`, which writes what it adds. Tracing raises when no group has a recorded test. `test/questionnaire_usage/generator_wiring_test.rb` runs the real generators in that order.

### The elements

```mermaid
flowchart TD
    usage["Each item use of a shown entry,<br/>except a variable definition"] --> path["Each element path it reads"]
    path --> checked{"Checked by any group the entry links to?<br/>Must Support, mandatory, id,<br/>or the value of a Must Support extension slice"}
    checked -- no --> notchecked["Group summary:<br/>Elements not checked"]
    checked -- yes --> own{"Checked by G's<br/>own profile?"}
    own -- no --> itemonly["Only in the item lines<br/>of the request's section"]
    own -- yes --> ms{"G has a<br/>Must Support test?"}
    ms -- yes --> mstest["Must Support test section:<br/>element: items that read it"]
    ms -- no --> itemonly
```

Item lines in every section also show each path, with "(not checked)" after the unchecked ones. `Delivery` decides this once for each entry, so every section and summary gives the same answer. A Must Support test lists only what its own group's profile checks, since that is all the test looks for.

### The group summary

It lists each questionnaire with the labels of the tests its entries went to, adding the Must Support test when its items read an element the group's own profile checks. `tested_by` in `questionnaire_usage.yml` holds the same tests' ids.

## Generated Markdown

Inferno shows tables without borders and raw HTML as text, so the sections use only nested lists, bold and plain text. Callers pass plain Markdown to `Generator::GroupDescriptions`, which escapes it for the group template.

## Layout

- `lib/inferno_suite_generator/questionnaire_usage.rb`: `QuestionnaireUsage.generate`, which traces the IG and writes the results
- `lib/inferno_suite_generator/questionnaire_usage/`:
  - `tracer.rb`: finds the sources in each questionnaire and the items that use them
  - `trace_entry.rb`: one source, with a class per kind that says whether it's shown, which test makes its request and how a section names it. Add a kind of source here.
  - `item_use.rb`: one item reading a source: how sections name it, what it does to the item, and its trace file fields
  - `ast.rb`: reads FHIRPath expressions to find the variables and element paths they use
  - `profile_matcher.rb`: matches a source to the groups whose profile it fits
  - `fhir_query.rb`: one x-fhir-query, parsed once: its resource type, whether it's a read, its search parameters, `_include` values and codes
  - `router.rb`: finds the test that makes each source's request
  - `delivery.rb`: decides which tests list each entry and which elements count as checked
  - `sections.rb`: writes every "Used in questionnaires" section a delivery decided on: the test sections, the Must Support sections and the group summaries
  - `trace_files.rb`: writes each group's `questionnaire_usage.yml`
  - `checked_elements.rb`: the rule for which element paths a group's tests check and how they are named, used by `delivery.rb`
- `lib/inferno_suite_generator/core/test_index.rb`: finds a group's tests by kind and details
- `lib/inferno_suite_generator/core/group_descriptions.rb`: collects and escapes the added description text
- `test/questionnaire_usage/`: unit tests for each class, plus `generate_test.rb`, which runs the tracing the way the generator does

## Test

```bash
bundle exec rake test
bundle exec ruby -Itest -Ilib test/questionnaire_usage/generate_test.rb
```
