---
lat:
  mode: explanation
---

# Why :unprocessable_entity is linted out

Rack renamed HTTP 422.

`:unprocessable_content` is the current name; `:unprocessable_entity` is deprecated, and Rack prints a warning on every use — so a run of the suite carried one line of noise per call, which is how real warnings get skimmed past.

## Why this is worth pinning

Both names still work and both still mean 422, so nothing breaks when the old one comes back.

That is exactly why this is worth pinning: `:unprocessable_entity` is the name most people already have in their fingers, Rails' own older guides use it, and a sweep that leaves no gate behind is a sweep somebody quietly undoes.

## The comment exception

Comments are left alone by `spec/lint/deprecated_http_status_symbol_spec.rb`. One spec explains why it asserts the number 422 rather than either symbol, and naming the deprecated spelling is the whole point of that sentence.

## Why the check lives entirely inside one example

Everything sits inside the example on purpose, for the same reason the sibling line-citation check gives: the type checker resolves neither a `def` inside a `describe` block nor a constant declared beside one.
