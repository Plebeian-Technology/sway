---
mode: reference
summary: "What resolveJsonPointerOffset does, the RFC 6901 escaping it undoes, and why it returns null rather than an exact offset on any failure or ambiguity."
status: agent-extracted
related: []
---

# `resolveJsonPointerOffset`

Turns a JSON Pointer into a character position in the raw text, as best it
can. A JSON Pointer (RFC 6901) is a path into a JSON document, written with
"/" between the steps, where "~1" stands for a literal "/" and "~0" for a
literal "~". This walks that path through the parsed document, then finds
the matched value's key again in the original text. It returns null on any
failure — unparseable JSON, a missing key, an ambiguous match — so the
caller can fall back to simply focusing the box.
