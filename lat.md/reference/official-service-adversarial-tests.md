---
lat:
  require-code-mention: true
---

# Official service adversarial tests

These independent checks verify source provenance and boundary interpretation beyond the basic configured-reader examples.

## Configured source controls retrieval

The official source URL controls the actual request even when injected transport has another base URL, preventing attribution to a source that was never retrieved.

## One response supports multiple retained records

Multiple service records retain the original response and remain independently supported; repeated retrieval reuses stable evidence without duplicate writes.

## Fact values agree with retained evidence

Changing a normalized title after parsing makes the fact unsupported because its values no longer agree with retained evidence.

## Unknown boundary meaning refuses service

Unspecified or unknown boundary semantics produce no supported service fact, so the reader cannot infer an inclusive or exclusive end date.

## Dirty evidence cannot authorize a fact

In-memory edits cannot masquerade as retained official evidence even when the altered fact agrees with them; the persisted record remains the source of authority.

## Persisted third-party provenance is unsupported

A persisted third-party record cannot qualify as official evidence solely through a caller-supplied supported capability label.

## Malformed configuration is explicitly unsupported

Invalid field and boundary mappings produce an explicit unsupported result without requesting an upstream source.

## Reading evidence does not create a locale

Evidence retrieval may retain its payload but cannot autosave an unsaved civic locale supplied to the reader.
