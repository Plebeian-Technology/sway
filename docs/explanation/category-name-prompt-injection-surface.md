---
mode: explanation
summary: "Why Category#name validation (length, control characters) lives on the model rather than at the two prompt builders that embed it unescaped."
status: agent-extracted
related: ["docs/explanation/bill-category-prompt-security.md", "docs/explanation/bill-summary-prompt-architecture.md"]
---

# Why Category#name validation lives on the model

<!-- vale Vale.Spelling = NO -->

A `Category#name` is more than a label. It goes word for word into the
cacheable system section of two prompts —
`BillSummaryPromptBuilder#categories_requirement_note` and
`BillCategoryPromptBuilder#system_prompt` — in both cases as a
comma-joined list on an instruction line ("choose 1-3 categories
from the active taxonomy: ..."). It is not cleaned, not collapsed, not
length-limited, and not quoted: the only value in either prompt that
reaches the model without any of those four protections.

## What the model checked before, and what it missed

The model originally checked only that a name was present and unique —
nothing about what it *contained*. A name with a newline in it could open
a line of its own inside the instruction block, and a name of any length
could swamp a cached opening section that has to stay byte-for-byte
identical to be worth caching at all.

## Why the fix lives on the model, not the prompt builders

Only admins write category names, so this is an extra layer rather than a
hole open to strangers — which is exactly why it belongs on the model,
where every writer passes through, instead of being cleaned up as the two
prompts are built. Cleaning the value at prompt-assembly time (the way a
bill title gets rewritten) was rejected: it would break
`BillCategoryAssigner`'s round trip, which matches the model's answer back
by `Category.slugify(name)` against these same rows. Rewriting a name at
prompt time could stop it matching its own slug.

This is an extra layer, not a complete guarantee: it does not cover rows
saved before these validations existed, or a write that skips validation
entirely (`update_column`, `insert_all`, raw SQL).

## Why the length cap is 100 characters

`Category::MAX_NAME_CHARS` is 100 against a longest real category name of
20 characters ("Technology & Privacy") — roomy enough for any sensible
label, tight enough that many names in a row still can't crowd out the
instructions around them in the cached prompt block.

## Why only control characters are refused, and why all of them

Of the characters `Category::NAME_CONTROL_CHARACTERS` refuses, the newline
is the one that actually matters for the prompt-injection risk: it is what
lets a name escape its comma-separated list and start its own instruction
line. The rest of the control-character range is refused too rather than
carved into an allow-list of exceptions — none of them belong in a display
label either.

## Testing a scrubbed copy, not the raw name

`Category#name_is_free_of_control_characters` runs the control-character
check against `Sway::Utf8.scrub(name)`, not the raw `name`, because
`String#match?` raises `ArgumentError` on bytes that are not valid UTF-8 —
which would turn an invalid name into a 500 instead of an ordinary
validation failure. A name with bad bytes still fails validation, since the
scrubbed copy that gets checked won't equal the original and won't match
the pattern either way.
