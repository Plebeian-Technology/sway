---
mode: reference
summary: "How BillAmendmentOperation's anchor_text/replacement_text columns are filled for each operation on a text-pattern match, and why enum :operation suppresses its class scopes."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# BillAmendmentOperation column contract

One `BillAmendmentOperation` row exists for every change to existing law
that `ParseSectionsService` spots by matching text patterns in a bill.
Today `:source` is always `:text_pattern`. `:markup` is set aside for a
future version that reads structured Akoma Ntoso markup — an XML format
for publishing legislation — instead of hunting through plain text.

## How the two text columns are filled for a text-pattern match

| operation | anchor_text | replacement_text |
|---|---|---|
| `:strike` | the matched text | `nil` |
| `:insert` | `nil` | the matched text |
| `:replace` | the matched text | `nil` |

A text-pattern `:replace` is not split into its old and new halves —
`apply_operations`, further down the processing chain, warns about that on
purpose rather than silently treating a half-populated replace as
equivalent to a strike.

## Why enum :operation passes scopes: false

`enum :operation, {strike: 0, insert: 1, replace: 2}, scopes: false`
suppresses the class-scope methods `.strike` / `.insert` / `.replace` that
`enum` would otherwise generate. `ActiveRecord::Base` already defines a
class method `.insert` for bulk-insert, so generating an enum scope of the
same name raises `ArgumentError` at load time. The predicate-style
instance methods (`#strike?` / `#insert?` / `#replace?`) and the enum
mapping (`.operations` / `.operations.keys`) are unaffected and still
generated.
