---
lat:
  mode: explanation
---

# Why the Object-spec-methods shim is a type-checking hole waiting to happen

`sig-test/object_spec_methods.rbs` declares one signature per method name for the whole `:test` steep target, and it hangs every one of them on `class Object`.

Declaring a common name there is not a helpful shim, it is a hole: every `receiver.call(...)` in every type-checked spec then resolves to `Object#call`, type-checks clean, and comes back as `untyped`. Steep can no longer catch a `NoMethodError` there or work anything out from the result.

That file's own policy comment (the `classifier_candidate` / `classifier_payload` block) already requires prefixing generic helper names for this exact reason. `spec/integration/object_spec_methods_shim_spec.rb` holds that requirement in place at the code level: it fails the build the moment a forbidden name is declared on `Object` in that file.

## Why this example needs no Rails, and why it boots Rails anyway

The example itself reads one file and runs one regular expression — no `Rails.root`, no `type:` metadata.

What it cannot avoid is the boot itself: `.rspec` carries a global `--require rails_helper`, so every spec in this project loads Rails whether it asks to or not. Swapping this file's own `require` for `spec_helper` would save nothing while looking like it did — the cost lives in `.rspec`, and moving it would be a change of its own.

## Why the forbidden list keeps growing instead of naming one method

An earlier version of this guard named exactly one method (`call`), so an author who later reintroduced the same hole under `result` or `perform` would have gone uncaught.

The forbidden list holds the most generic names that are not currently declared, so adding any of them trips this example instead of quietly erasing type checking across the target. Widening the set is always the right direction; narrowing it is not.

As measured at extraction, the list was `call result perform execute value data id to_s each map subject response error message` — verify the current set against `spec/integration/object_spec_methods_shim_spec.rb` rather than trusting this snapshot, since the same drift that grew the list once (an earlier version listed eight names and was three short) can grow it again.

## Known gap: names already in the shim before this guard existed

`raise`, `new`, `first`, `find`, `select`, `name`, `status`, `params`, `run`, `key` and `body` have the same defect and are deliberately not asserted by this spec.

`raise`, `new`, `first`, `find`, `select`, `name`, `status`, `params`, `run`, `key` and `body` have the same defect and are deliberately not asserted by this spec — they predate this guard, and removing them is its own job, not a side effect of adding new names to the forbidden list.

## Why call is listed first, and why the list is local variables, not constants

`call` comes first because it is the most generic method name in Ruby, and a `subject(:call)` in `summary_citation_validator_spec.rb` had already dragged it in once.

The forbidden list and the shim path are plain local variables rather than constants, because a constant defined inside an RSpec block lands on `Object` — the very hazard this file guards against.
