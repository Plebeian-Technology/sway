---
lat:
  mode: reference
---

# resolveJsonPointerOffset

Turns a JSON Pointer into a character position in the raw text, as best it can.

- A JSON Pointer (RFC 6901) is a path into a JSON document, written with "/" between the steps, where "~1" stands for a literal "/" and "~0" for a literal "~". This walks that path through the parsed document, then finds the matched value's key again in the original text. It returns null on any failure — unparseable JSON, a missing key, an ambiguous match — so the caller can fall back to simply focusing the box.

## Parent container tracking and approximate key lookup

[[app/frontend/components/admin/creator/paste-summary/resolveJsonPointerOffset.ts#resolveJsonPointerOffset]] tracks the parent container while walking the parsed JSON value and locates the target key in the raw text.

- Recording the parent container distinguishes an array index from a numeric object key (such as "/0" on {"0": "x"}).
- When the final segment is an array index rather than a searchable key name, the lookup targets the parent key holding the array instead.
- Raw-text key search is an approximate jump rather than a full lexer, returning the first matching key offset or null.
