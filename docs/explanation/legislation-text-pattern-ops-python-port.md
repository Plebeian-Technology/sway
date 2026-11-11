---
mode: explanation
summary: "Why Legislation::TextPatternOps is a word-for-word port of the frozen Python section parser's text-pattern fallback, and how its regex flags translate from Python to Ruby."
status: agent-extracted
related: [seed-bill-legacy-python-sidecar]
---
<!-- vale Vale.Spelling = NO -->

# Legislation::TextPatternOps: a word-for-word port of the Python section parser

`Legislation::TextPatternOps` is a word-for-word port of the older Python
section parser's `text_pattern_fallback()`. It covers the text-pattern
fallback only: it spots amendment wording by matching phrases. Reading
amendment markup out of the PDF itself is NOT implemented here.

The markup JSON files the old Python pipeline produced are NEVER read by
this Ruby code — that pipeline is frozen and switched off (see
[Why SeedBill kept its old public API](seed-bill-legacy-python-sidecar.md)
for the broader Python-to-Rails migration this belongs to).

`TEXT_PATTERN_OPS` is carried over unchanged from the Python parser.
`.text_pattern_fallback` is carried over unchanged from the Python parser's
`text_pattern_fallback()` too, and returns plain Hashes, not database
rows — the caller opens the transaction and fills in each operation's
position in the order and which section it belongs to.

## Translating the Python regular-expression flags

`re.DOTALL` becomes Ruby `/m` (makes `.` match a newline too);
`re.IGNORECASE` becomes Ruby `/i`.

`re.MULTILINE` is a DIFFERENT flag from Ruby's `/m` — it changes what `^`
and `$` anchor to, while Ruby's `/m` changes what `.` matches. Do NOT reach
for Ruby's `/m` thinking it means the same thing as Python's
`re.MULTILINE`.
