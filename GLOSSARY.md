# Inferno Suite Generator

Generates Inferno test suites from a FHIR Implementation Guide. This glossary covers the language of questionnaire usage tracing, which shows testers how the IG's SDC questionnaires depend on what each test checks.

## Language

### Suite

**Group**:
The generated set of tests for one profile.

**Must Support test**:
The test in a group that looks for the elements its profile marks Must Support.

### Questionnaire sources

**Source**:
Something in a questionnaire that links it to a resource type: an `x-fhir-query` variable, a launch context or a template extract.
_Avoid_: Reference, dependency

**FHIR query**:
An `x-fhir-query` parsed once when its source is traced. It says what the query asks for: its resource type, whether it reads one resource, and its search parameters, `_include` values and codes.
_Avoid_: Query, which here names the kind of source

**Trace entry**:
The record of one source for one resource type, with the items that use it. A query has one for its own type and one for each `_include` target, and the groups a source links to share its entries.
_Avoid_: Usage, trace item

**Trace**:
The trace entries of every questionnaire in the IG, each with the groups its source links to. Groups that link to one source share its entries.

**Item use**:
One form item, or the questionnaire root, reading a source through an expression. An expression that only defines a variable isn't an item use: the items that read the variable are.
_Avoid_: Usage, reference

**Shown entry**:
A trace entry worth listing for testers, because an item uses it, it is a template extract, or it is a query that fetches other resources through `_include`.
_Avoid_: Visible entry

### What tests cover

**Request test**:
The test that makes the same request as a trace entry's source, or for a template extract the test that writes that resource. It can belong to another group, as an `_include` request does.
_Avoid_: Source test, matching test

**Delivery**:
The decision of which tests list each trace entry and which elements its items read count as checked. The test descriptions and group summaries both state this one decision.
_Avoid_: Routing, which only picks the request test

**Placement**:
One trace entry of one group, with the tests that list it: its request test, and the group's Must Support test when its items read an element that group's tests check. It also records whether each element its items read is checked.
_Avoid_: Destination, which names only one of those tests

**Checked element**:
An element path a group's tests check: its profile marks it Must Support or requires it, it is `id`, or it is an extension the profile marks Must Support or that extension's value. For a trace entry shared by several groups, an element is checked when any of them checks it.
_Avoid_: Must Support element, which leaves out required elements and `id`

### What tracing writes

**Section**:
The "Used in questionnaires" Markdown added to a description: a test section for a test that makes a request, a Must Support section, or a group summary.
_Avoid_: Usage section, which named only the list of sources
