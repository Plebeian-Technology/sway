---
lat:
  mode: explanation
  require-code-mention: true
---

# Influence page browser coverage

The system examples verify the signed-in Influence page across its loaded, empty, and error outcomes.

## The system examples cover the signed-in page outcomes

These examples drive the actual page and its data states in a browser; lower-level request behavior is covered by request specs.

## Redirect cases belong to request coverage

The system file does not duplicate authentication and missing-resource redirect branches. Those response contracts are checked at the request boundary, while these browser examples focus on rendered page states.
