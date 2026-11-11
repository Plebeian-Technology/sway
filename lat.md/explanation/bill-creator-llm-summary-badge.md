---
lat:
  mode: explanation
---

# BillCreatorLlmSummaryBadge

Why BillCreatorLlmSummaryBadge's wording matches the old badge word for word, why a reclaimable pending/generating row shows Abandoned instead, and why a skipped row gets a neutral tone.

## Why the wording matches the old badge word for word

The stamp-style pill showing how far along the LLM summary is. The wording matches the old badge word for word, so the QA scripts that look for it keep working.

## Why reclaimable exists as a separate prop

The server's judgement that a `pending`/`generating` row has no live writer (BillLlmProvisioning#reclaimable?).

Without it, an abandoned row would still show "Queued…"/"Generating…" directly above LlmSummaryAbandonedRunNotice saying nothing is working on it.

A reclaimable pending/generating row has no worker behind it, so "Queued"/"Generating" is a claim it can't back up — say what the row is instead of contradicting the notice next to it.

## Why a skipped row gets a neutral tone

An out-of-date job was passed over because a newer one replaced it, not because it failed. A plain tone avoids reading as an error, and Generate/Regenerate stays available.
