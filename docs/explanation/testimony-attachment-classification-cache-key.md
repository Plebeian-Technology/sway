---
mode: explanation
summary: "Explains why TestimonyAttachmentClassification caches only the language-model step, why its key excludes source_endpoint but includes sway_locale_id, and the history behind three deleted members that would reintroduce the same stale-cache bug."
status: agent-extracted
related: [docs/explanation/classification-model-switching-cost.md, docs/explanation/testimony-classification-migration-dedup-bug.md]
---
<!-- vale Vale.Spelling = NO -->

# TestimonyAttachmentClassification's cache key design

`TestimonyAttachmentClassification` caches one saved answer from the
language model about one Legistar attachment: is this testimony or not.

## Why the cache read rescues broadly

`Testimony::AttachmentClassifier#cached_label` rescues broadly,
matching the cache write's own rescue: a failure here must never escalate
into a stage-level pipeline failure that kills every remaining bill, since
finding nothing is always a safe answer — the document simply falls
through to the model step or the "keep it" default. With no model
connection (tests, misconfiguration), no query is sent at all.

## Why only the model's answers are cached

`Testimony::NameRules`' plain allow/deny pattern rules run first and cost
nothing to re-run, so caching their output would buy nothing while
freezing an edited rule out of attachments already classified under the
old one. Only the paid language-model step is worth caching. Legistar
attachment ids never change, so a saved model answer makes every later
fetch of the same attachment free — until the model or prompt changes (see
[the model-switching cost doc](classification-model-switching-cost.md) for
what happens then). `source_endpoint` only records where an attachment
came from; it plays no part in the cache key (see below).

## Why source_endpoint is deliberately NOT part of the key

Legistar's two attachment collections share one id pool —
`EventItemMatterAttachments` is a view onto `MatterAttachments` — so
including `source_endpoint` in the uniqueness key would mean re-paying the
model whenever a per-event fetch failed and the OTHER collection won the
race to classify the same attachment first. The attachment is the same
attachment either way; which endpoint happened to surface it first is not
a reason to pay twice.

## Why the key is (sway_locale_id, attachment_id), not attachment_id alone

`attachment_id` alone quietly assumed a single jurisdiction — only
Baltimore exists today — and would collide two different locales'
attachment `38947` into one shared row once a second locale existed. The
matching assumption in sidecar filenames was fixed in the same change (see
`Legislation::Paths.attachment_dir`).

## Why for_verdict matches on model AND prompt_version

`model` used to be written on every row but never read, so a saved answer
was effectively permanent: swapping the classifier model, or fixing a
flawed prompt, could never re-classify a stale `"not_testimony"` row.
`.for_verdict` now matches on `sway_locale_id`, `attachment_id`, `model`,
AND `prompt_version` together, so either change causes the next run to
miss the cache and re-classify. Rows written before `prompt_version`
existed hold `NULL` and match nothing under this scope, which is the
correct outcome: nobody can tie an old verdict back to a real prompt
version, so it can't safely be trusted as still current. (See [the
migration dedup bug doc](testimony-classification-migration-dedup-bug.md)
for a related failure mode in how duplicate rows under an earlier,
narrower key used to get collapsed.)

## Three deleted members, and why they aren't coming back

Three things used to live on this model and were deliberately deleted
rather than kept beside their replacements:

- A `for_attachment` scope keyed on `attachment_id` alone. An answer is
  only trustworthy for the specific model and prompt that produced it —
  the same gap `.for_verdict` closes — so a scope that ignores both is
  the wrong tool a future reader could reach for by accident.
- An `attachment_name` column, written on every verdict but read by
  nothing in `app/`, `lib/`, or `sig/`. An unread column is
  the wrong one a future reader reaches for by accident, the same
  reasoning as the deleted scope.
- A `#testimony?` method with no caller anywhere.
  `Testimony::AttachmentClassifier` compares `cached == TESTIMONY` itself,
  on a row already loaded through `.for_verdict`. Reading `label` directly
  without going through a method that also matches `model` and
  `prompt_version` would reintroduce the exact "wrong forever" cache bug
  `.for_verdict` exists to prevent.
