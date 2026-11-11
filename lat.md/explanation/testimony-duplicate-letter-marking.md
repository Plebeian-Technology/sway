---
lat:
  mode: explanation
---

# Why a repeated letter is marked, not deduplicated away

Baltimore sometimes publishes the same public-testimony bundle twice for one bill — once per hearing, when a submission carries over between hearings on the same bill.

`FetchHearingsService#compose_testimony_from_disk` concatenates every attachment's text with no deduplication of any kind, so a letter published at both hearings arrives at `Testimony::CleanAndGroupService` as two separate letters. `Testimony:: DuplicateLetterMarker` marks the second (and any later) copy; this document explains what it matches on and why the mark is additive rather than a deletion.

## Keep both, mark the later one

A duplicated letter is real evidence that a campaign or an individual resubmitted testimony across hearings — deduplicating it away in `Testimony::LetterSplitter` would erase that fact.

Instead every copy stays in the artifact's `letters` array, and the later one carries `"repeat" => true` plus `"repeat_of_position"`, naming the earlier letter's own `"position"`. Everything downstream that counts distinct submissions — `Testimony::CampaignMarker#finalize_draft`'s `letter_count` and `Testimony::DomainCountsWriter`'s per-domain `letter_count` — excludes a repeat; everything that still wants the raw population (`letter_positions` on a `Testimony::CampaignDraftFinder` draft, `Testimony::CoverageReport#total_letters`) keeps it.

## What counts as a repeat

Two letters are matched on the SAME NON-BLANK sender address plus the SAME normalized body.

Two letters are matched on the SAME NON-BLANK sender address plus the SAME normalized body — the mail envelope (`From:`/`Sent:`/`To:`/`Subject:`) stripped first, the same way `Testimony::CampaignDraftFinder::paragraphs_for` drops it, because the two copies carry two different `Sent:` timestamps and would otherwise never match. The body comparison then joins every non-blank normalized line and hashes the result — whitespace and case differences are ignored, but a genuinely reworded resubmission is never treated as a repeat of the first.

A letter with no sender address is never marked a repeat of anything, even of a byte-identical body — an anonymous letter's own text is the only signal available, and matching two anonymous letters against each other risks collapsing two different anonymous senders who happened to write something similar. This is a known gap, not a decision that anonymous duplicates never happen; a measurement found 4 of 222 letters on bill 25-0064 with no address at all.

## Why the false-negative direction was chosen

Marking a genuine distinct submission as a repeat erases a person from the count entirely, which is worse than leaving one duplicate uncaught.

The matching rule above is biased toward under-marking on purpose: a truncated attachment (the per-attachment character cap) or a mis-parsed mail header will make two real copies of one letter normalize to different text and go unmatched, rather than risk one false match. Because of this, the marker's own accuracy is independent of both the per-attachment cap and the header-parsing bug — fixing either can only let it catch MORE real duplicates, never fewer.

## Why the coverage report's letter totals were left alone

`Testimony::CoverageReport::Result`'s own comment documents an invariant.

`Testimony::CoverageReport::Result`'s own comment documents an invariant: `reached_letters + left_out_letters` sums to `total_letters`, and `reached_letters` comes from `BillPositionsPromptBuilder#testimony_reach`, which is not aware of the "repeat" mark and still counts every letter it walks. Subtracting repeats out of `total_letters` alone would make `left_out_letters` negative on a bill with real duplicates, breaking that sum. `repeat_letter_count` was added as a new, independent field instead — it reports how many of `total_letters` are repeats without touching the existing three.

Whether a duplicate letter should also be excluded from what actually reaches the model in `BillPositionsPromptBuilder` — spending prompt budget and, on a large enough bill, model attention on the same letter twice — is a separate, larger decision (LLM cost, output bias) left as a follow-up. It is coupled to the per-attachment and per-bundle character caps (`FetchHearingsService::MAX_ATTACHMENT_TEXT_CHARS`, `MAX_COMPOSED_TESTIMONY_CHARS`), which a later phase item owns.

## A draft can now report fewer letters than CampaignDraftFinder::MIN_LETTERS_FOR_REUSE

`Testimony::CampaignDraftFinder` only ever forms a draft from at least `MIN_LETTERS_FOR_REUSE` (2) distinct letters.

`Testimony::CampaignDraftFinder` only ever forms a draft from at least `MIN_LETTERS_FOR_REUSE` (2) distinct letters — grouping runs before duplicate marking has any effect on it, so that invariant holds at the moment a draft is formed. But a draft whose only two members are the SAME letter published twice now reports `letter_count: 1` after exclusion: one resident's one letter, not a campaign of two. This is not a new kind of draft — the shared-text draft already existed and was already shown to an operator, previously reporting 2 — it is a new visible COUNT on an existing draft.

This document deliberately does not redesign grouping to drop such a draft below the threshold. The double-counting report already warns that a shared draft id across two hearing bundles "does NOT on its own prove cross-bundle campaign identity," and dropping the draft would erase the very evidence — that this sender submitted the same letter twice — that made the draft worth forming in the first place. `TestimonyCampaignDraftResource`'s `repeat_letter_count` attribute exists so the operator can tell a real 1-letter draft (a repeat excluded) from an undeduped 1-letter reading, on the same card that shows `letter_count`.

## sender_count was already partly protected

`Testimony::CampaignMarker#finalize_group`'s `sender_count` counts distinct KNOWN sender addresses (`.uniq`) plus one per blank-address letter.

Two copies of the same letter from the same known address already collapsed to one sender before this change, for that reason alone — `letter_count` (a raw `members.length`, no dedup at all) was the count actually inflated by a repeat. The residual gap `sender_count` still has is the same one `DuplicateLetterMarker` has: a blank-address repeat, or a same-letter pair whose address extraction diverges between the two copies.

## The model no longer reads a repeat twice

[[app/services/bill_positions_prompt_builder.rb#BillPositionsPromptBuilder]] excludes repeated letters from the positions prompt while crediting them in reach calculations.

`BillPositionsPromptBuilder#labeled_letters` rejects a letter whose `"repeat"` key is truthy, using the exact same `letter["repeat"]` truthiness test as `Testimony::CampaignMarker#finalize_group` and `Testimony::DomainCountsWriter`, so a missing key (an artifact cleaned before `DuplicateLetterMarker` existed) still reads as "not a repeat." Only the later copy is dropped — the earlier letter a repeat duplicates keeps its place, exactly as `CampaignMarker`'s `letter_count` already treated it.

`#labeled_reach` explicitly credits excluded repeat letters from `artifact["letters"]` toward `reached_letters` and adds their raw character slice lengths to `reached_chars` without consuming prompt character budget. In earlier versions, walking only the filtered list caused repeats to be counted as `left_out_letters` and `left_out_chars` in `Testimony::CoverageReport`, triggering false coverage gaps that blocked automated approval. Crediting repeats in `#labeled_reach` ensures `CoverageReport` reflects that repeats were accounted for by the pipeline in their initial instance, preserving zero left-out counts when all distinct letters fit in the budget.

The unlabeled fallback path (`#unlabeled_cleaned_reach`, an artifact older than the kind-of-source stage) is unchanged: it sends the artifact's raw `"text"` unmodified rather than rebuilding it letter by letter, so there is no per-letter join to drop a repeat from — fixing that would mean redacting byte ranges out of a raw string, a larger change than this ticket scoped.
