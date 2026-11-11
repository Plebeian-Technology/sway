---
lat:
  mode: explanation
---

# What the bill provisioning JSON payload sends, and what it deliberately drops

`BillLlmProvisioning#to_builder` is a Jbuilder block that feeds `Bill#to_builder`.

This document covers two fields that used to be sent and were deliberately removed, and why the builder itself has not yet moved to an alba resource.

## diff_content is not sent

The note that used to sit here said `diff_content` was needed so the Bill Creator could tell "the pipeline produced data" apart from "the pipeline produced none" — a rule the code did not actually keep.

That screen decides on whether a provisioning row exists at all (`LlmSummaryEmptyState`), and nothing in the modern frontend or the mobile app ever read the key. The only reader was a card in the since-deleted V1 tree, which could not load, because no controller asked for that layout.

Sending it was not free. This builder is rebuilt on every `bill` prop build, which on the Bill Creator's summary tab means every five-second poll and every cable-triggered reload. Every provisioning row carries a diff, and once the JSON document inside is escaped into a JSON string it runs to kilobytes on the wire. Sway's readers are assumed to be on much slower links than the dev host, so a repeated payload nobody reads is exactly the cost that does not show up locally.

## diff_generated_at is gone too

Not for its size — a timestamp costs nothing — but because nothing reads it any more.

Its one reader was the out-of-date marker's wording, and the marker now reads `stale_change_at` instead, because the diff is only ONE of the two things that can overtake a summary; quoting it when testimony was the actual cause is the bug that was fixed. See [[docs/explanation/stale-change-detection.md|What makes a bill summary stale]] for the full account of how the change kind is computed. Nothing in the mobile app read `diff_generated_at` either.

`stale` itself comes from `#stale_change`, which is `#stale?` itself. An older note here said the rule was "the diff being newer than the summary", and that stopped being the whole rule when testimony gained an arm — again, see [[docs/explanation/stale-change-detection.md|What makes a bill summary stale]].

## Why four testimony/citation fields stay on the older Jbuilder path

The testimony and citation fields the browser needs.

The testimony and citation fields the browser needs — `testimony_attachments`, `citations_valid`, `invalid_citations`, and `has_testimony` — stay on the Jbuilder path rather than moving to an alba resource, and that was decided, not overlooked. `extracted_testimony` itself is deliberately left out of the payload: it only feeds the AI call and can be any length at all.

CLAUDE.md says new JSON goes through an alba resource and that existing `to_builder` code moves across when convenient. Adding keys to an old builder sits right on that line — but there is no `BillLlmProvisioningResource` yet to be inconsistent with, and this builder runs inside `Bill#to_builder`, so moving only part of it would leave TWO ways of building JSON for one set of related objects. That is worse than one old path: it is exactly the shape that produces a fix applied at one call site when there are two, which is the kind of bug this work keeps running into.

Moving this across is whole-object work and belongs to the wider serializer migration, along with the exact key-set request spec CLAUDE.md asks for. Written down here so the next reviewer does not raise it again as an unexamined violation.
