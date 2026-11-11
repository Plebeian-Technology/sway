---
mode: explanation
summary: "Why Testimony::CoverageReport's acknowledgement digest includes state, and why removed_chars clamps to zero instead of going negative when character repair adds more characters than the banner strip removed."
status: agent-extracted
related: []
---
# Why the coverage digest includes state, and removed_chars clamps to zero

<!-- vale Vale.Spelling = NO -->

## The acknowledgement digest includes `state`

`Testimony::CoverageReport::Result#digest` fingerprints every field in
`digest_fields`, including `state`. A stage merely *starting* to run does
not change any number the operator already read — the client already
disables the acknowledge button while a run is in flight — but the same
numbers can carry a different meaning depending on how they were produced.
`:never_run` and `:failed` can report identical `total_chars`,
`reached_chars`, `removed_chars` and `left_out_chars` (no clean-testimony
pass ever completed in either case), yet they are not the same situation an
operator signed off on: one means clean-testimony has never been attempted,
the other means the last attempt errored out. Including `state` in the
digest means an acknowledgement recorded under one does not silently cover
the other. `spec/services/testimony/coverage_report_spec.rb`'s "the digest
" example pins this: `never_run_result.digest` and
`failed_result.digest` differ even though every other field matches.

## `removed_chars` clamps to zero; `repair_added_chars` is the separate growth field

"Removed as repeated" chars is `[total_chars - cleaned_chars, 0].max` —
clamped to zero, not allowed to go negative. The character-repair step can
add a couple of characters back for every broken word it resolves, so a
bill whose repair growth outweighs its (small or absent) banner could
otherwise make this subtraction negative. Rather than let `removed_chars`
carry that negative value, the growth is captured in its own field,
`repair_added_chars` (`[cleaned_chars - total_chars, 0].max`), clamped the
same way from the other direction. `removed_chars` is one of the three
fields (`reached_chars`, `removed_chars`, `left_out_chars`) the `Result`
docstring guarantees always sum to `total_chars`; letting it go negative
would break that invariant, so the growth case is routed to
`repair_added_chars` instead, which sits outside the sum.
