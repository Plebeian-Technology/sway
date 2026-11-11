---
mode: explanation
summary: "The design concepts behind BallotHomeLayout and ChamberHomeLayout, Sway's themed public landing page layouts."
status: agent-extracted
related: []
---

# Themed home layout design concepts

## `BallotHomeLayout`

Shows the landing page like the sample ballot that arrives in the mail
before an election — a header, numbered instructions for the voter, and
signing in framed as checking in at the polls. One paper-like surface
marked off by scanner-style rules, matching the bill layout: no cards, no
shadows.

Its `INSTRUCTIONS` list is numbered because ballot instructions are
genuinely a sequence — a voter is told to do these things in this order —
so the numbering encodes something true rather than decorating three
unordered value propositions.

## `ChamberHomeLayout`

Shows the public landing page like the chamber doors opening — a
plaque-style hero section with a brass-colored rule, the passkey sign-in
panel framed as the members' entrance, and the value propositions listed
like a formal order of business. Reuses the same dark, formal-agenda look
as the chamber bill-detail page.
