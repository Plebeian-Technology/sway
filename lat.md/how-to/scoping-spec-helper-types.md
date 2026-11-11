---
lat:
  mode: how-to
---
# Scope spec helper types

Extract duplicate spec helpers from top-level example groups into named support modules with explicit RBS signatures to eliminate global Object pollution and prospective method collisions.

## Steps

Follow these steps to migrate duplicate or un-namespaced spec helpers into a scoped support module.

1. Identify duplicate helper methods across spec files (e.g. `max_chars` or `current_digest`) that lack namespacing and pollute `class Object`.
2. Extract helpers into a dedicated support module in `spec/support/<name>_spec_helpers.rb` with an exact `@lat: [[scoping-spec-helper-types#Scope spec helper types]]` reference. Do not use `RSpec.configure` global inclusion; explicitly include in consumer specs.
3. Require the new support file in `spec/rails_helper.rb` alongside the other support modules.
4. In targeted spec files, add `include <Name>SpecHelpers` inside the example group and delete duplicate local method definitions.
5. Declare the support module in `sig-test/support/<name>_spec_helpers.rbs` with its exact return types.
6. Maintain mirrored declarations on `class Object` in `sig-test/object_spec_methods.rbs` with an explanatory comment citing the module and explaining RSpec's untyped block evaluation in Steep.
7. Run both `bin/steep check --severity-level=information` and `lat check && lat check mode` alongside targeted RSpec specs and linters to verify runtime execution, static typing, and link integrity.

## Outcome

Spec helpers execute through modular inclusion rather than global `::Object` monkey-patching, keeping RBS signatures strictly scoped and preventing cross-spec method collisions.
