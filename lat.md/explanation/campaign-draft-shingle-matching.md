---
lat:
  mode: explanation
---

# Shingle matching alongside physical-line matching

`Testimony::CampaignDraftFinder` matched reused text at one grain only: the normalized PHYSICAL LINE.

That grain under-merged one campaign into eight separate drafts on bill 25-0064, even though the letters were measurably one campaign by other signals (three or more bill-number tokens in the opening 200 characters, one 6-letter shared opening spanning 3 group ids).

## Why a shared line can be zero, even for identical copies

A line break is a property of the source PDF, not of the letter.

The same sentence wraps at a different column in a different hearing bundle — one extraction breaks after word 9, another after word 11 — so two verbatim copies of one template can carry zero identical normalized lines. Union-find makes matching transitive (one shared line anywhere merges the whole component), so eight distinct drafts is only possible when those eight piles share literally no identical line at all.

## Why shingling is additive, never a replacement

The fix keeps physical-line matching exactly as it was and adds a second, independent signal.

The fix keeps physical-line matching exactly as it was and adds a second, independent signal: every 8-consecutive-word sliding window ("shingle") of a paragraph's flowing text (newlines replaced with spaces, so a wrap point cannot separate two words that were always adjacent in the sender's own text). A shingle hash and a physical-line hash feed the same union-find keyspace, under different node prefixes (`"phrase:HASH"` / `"shingle:HASH"`), so a match on either grain merges the same way. Because union-find only ever adds edges, no letter that used to share a draft can ever lose it — shingling can only merge two drafts the line matcher already treats as unconnected, it can never split one the line matcher already formed.

## Why 8 words, not fewer

`MIN_PHRASE_CHARS` (25 alphabetic characters) is roughly a four-word bar for a physical line.

Eight consecutive words is a stricter coincidence bar than that — two people do not independently write the same eight-word run any more than they independently write the same 25-character sentence, so shingling does not loosen what counts as reuse; it only catches the case where a real line match failed for a reason that has nothing to do with whether the text was actually reused (the wrap point). A paragraph with fewer than 8 words is skipped for shingling entirely — there is no partial window, and a short paragraph already gets its chance at a match on the line grain if it is long enough there.

## Why the draft id folds in both grains

A draft's id is a digest of the reused hashes its component carries, sorted for determinism across runs.

A draft connected only through shingles (no physical line matched) still needs a stable, non-colliding id — hashing an empty phrase list would give every shingle-only draft on a bill the same id. The digest input is therefore the sorted union of both the phrase hashes and the shingle hashes recorded on that component, never phrase hashes alone.

## Why added_words stays line-based

`added_words` is what an operator reads on the campaign draft card, and what feeds the positions prompt — it names the lines a sender wrote that were NOT part of the reused template.

Shingle matching exists only to decide which letters land in the same draft; it does not participate in deciding which of a letter's own lines get reported as "added." Changing that computation to shingle grain would report line fragments rather than the sender's own lines, which is a different, unrequested change to what the operator sees.

## Why line candidates count alphabetic characters and require two letters

[[app/services/testimony/campaign_draft_finder.rb#CampaignDraftFinder]] requires a normalized line to carry at least `MIN_PHRASE_CHARS` alphabetic characters and appear across at least `MIN_LETTERS_FOR_REUSE` distinct letters before counting as reused.

Counting alphabetic characters rather than raw string length excludes formatting lines, city-and-ZIP headers, and short salutations without maintaining a hand-written stoplist. Requiring at least two distinct letters keeps lone template letters out of text-reuse grouping; lone letters from confirmed sending-service domains are marked later by [[app/services/testimony/campaign_marker.rb#CampaignMarker]] on origin rather than text reuse.
