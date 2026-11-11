---
lat:
  require-code-mention: true
---

# Generic HTML session tests

The HTML session regressions verify the discovery boundary described in [[legislation-pipeline#Upstream jurisdiction adapters]].

## Session precedence

Stubbed HTML discovery verifies configured-session priority, database upstream naming and name fallback with literal endpoint and PDF expectations, protecting successful session selection.

## Locale documents cannot supply missing sessions

A locale without an active database session rejects discovery even when a stubbed locale document has an active session and its corresponding HTTP response contains a bill, preventing implicit document discovery.

## Missing locale rejects discovery

Discovery without a locale or configured session raises the missing-session processing error, preventing an unresolved session from appearing to be a successful empty result.

## Whitespace names reject discovery

Blank configured, upstream and database names raise the missing-session processing error, preventing whitespace from bypassing the session requirement.
