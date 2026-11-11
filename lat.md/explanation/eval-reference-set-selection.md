---
lat:
  mode: explanation
---
# Why the bands are taken whole rather than sampled

`Eval::ReferenceSetSelector` chooses the 30-bill reference set the eval harness scores every candidate against, re-deriving every number it produces from the machine it runs on rather than trusting an earlier measurement.

The band tally, the truncation boundary, and the chosen ids are all computed fresh on every call — never carried over from a prior run.

## Why the bands are taken whole rather than sampled

The truncation band (testimony over the model's context cap) and the 50k-cap control band are both taken WHOLE, never sampled, because a random draw of 30 bills from the corpus would miss the truncation case about half the time.

The failure the whole phase exists to catch — a model returning a confident, schema-valid, wrong answer once its source text gets cut off — can only show up in a bill that was actually truncated. A reference set that happened to skip every over-cap bill would never exercise that failure at all, which is why the selection method takes both edge bands whole and only samples (in the loose "fills the remainder" sense) the well-behaved bulk of the corpus underneath them.

## Why the numbers cannot be carried over from the earlier measurement

The 30 bill ids and band counts the earlier research pass produced were measured against a different population entirely — 166 bill folders under a directory layout, not this machine's database and its regenerated diff-markdown artefacts.

Carrying those ids or counts forward would silently describe a corpus this phase no longer reads. `Eval::ReferenceSetSelector` re-runs the whole measurement — the band tally, the truncation boundary, the chosen ids — against whatever the local database and `LEGISLATION_ROOT` hold today, and `sway:eval:reference_set` commits that run's own stdout beside the machine-readable set (`eval/reference-set.txt`), so a later reader can reproduce the choice instead of trusting it.

## Why the truncation boundary is a method call, not a constant

`BANDS`' truncation/control boundary and `SOURCE_CHAR_BANDS`' over/under-cap boundary are both read fresh inside `#call`, never baked into a literal or a load-time constant.

They call `BillPositionsPromptBuilder.max_testimony_chars` and `BillSummaryPromptBuilder.max_source_chars` directly. A boundary computed once at class-load time would freeze whatever the setting happened to be the first time the class was autoloaded, in whichever process loaded it first — and would then silently disagree with the actual value `BillPositionsPromptBuilder` uses once a setting changed, or once a test overrode it with `with_app_config`. Reading the boundary fresh on every `#call` is what lets `spec/services/eval/reference_set_selector_spec.rb` prove the boundary moves with the settings it is derived from, rather than merely trusting that the source doesn't restate it as a literal.

## What 30 bills buys and what it does not

Thirty bills, split 24 scored on both answer types and 6 scored on the summary type alone, is enough to see a model that is clearly unusable next to one that is fine.

It is not enough to separate two close models honestly — a run coming back 7.1 against 7.4 on this size of set is noise, not a finding, and no report built on top of this selection should present its numbers as finer than that. The earlier research pass already settled that limit.

## Why the task commits its own stdout

`sway:eval:reference_set`'s printed report is written verbatim to `eval/reference-set.txt`, committed beside the machine-readable `eval/reference-set.json`.

The report carries the corpus count, the per-band tally, the truncation boundary and where it came from, and the chosen ids grouped by band. A choice reproducible only by re-running the task on the same machine, at the same moment, against the same corpus is not reproducible in any way a later reader can check without also having that exact setup. Committing the run's own output turns "trust this set" into "diff this set against a fresh run" — the same shape `lib/tasks/classification_corpus_measure.rake` uses, chosen because that task's own history is the cautionary tale: it read a directory layout nothing had written in a year and could never refresh its own numbers.

## How ReferenceSetSelector defines its band thresholds and exclusions

[[app/services/eval/reference_set_selector.rb#ReferenceSetSelector]] enforces corpus prerequisites, deterministic tiebreaking, substitution bounds, and summary-source reporting across the 30-bill reference set.

[[app/services/eval/reference_set_selector.rb#ReferenceSetSelector#sort_band]] orders bills by descending testimony length and ascending `external_id` so selection never depends on database row order. [[app/services/eval/reference_set_selector.rb#ReferenceSetSelector]] fails when fewer than [[app/services/eval/reference_set_selector.rb#ReferenceSetSelector]] bills carry a summary source without testimony, [[app/services/eval/reference_set_selector.rb#ReferenceSetSelector]] rejects manual substitutions outside `:bulk_10k_50k`, and [[app/services/eval/reference_set_selector.rb#ReferenceSetSelector]] refuses bills lacking on-disk diff markdown rather than falling back to extracted text. [[app/services/eval/reference_set_selector.rb#ReferenceSetSelector]] reports how many chosen bills cross `BillSummaryPromptBuilder.max_source_chars` without altering testimony-band stratification.
