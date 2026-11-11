---
mode: explanation
summary: "Explains why LawSection's uniqueness index is corpus-agnostic and how LawSectionUpsert detects a cross-corpus key collision that index alone cannot prevent."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why LawSectionUpsert detects cross-corpus key collisions

`FetchLawService::LawSectionUpsert.call` saves one `LawSection` row,
updating in place when the row already exists — so re-running the pipeline
never creates duplicates. Rows are unique per `(sway_locale_id, key)`,
enforced by the database index `idx_law_sections_on_locale_key`.

## Why the uniqueness index ignores the corpus

The `(sway_locale_id, key)` index ignores the corpus (charter vs code) on
purpose — the key `"art_N__sec_M"` leaves out `corpus_type` because
bill-amendment citations (matched via
`ParseSectionsService#normalize_to_key`) cannot know which corpus they
cite when they build that same key.

## The cost, and how LawSectionKeyCollisionError catches it

If charter and code shared an article/section number, whichever loaded
last would silently overwrite the other's body. `LawSectionKeyCollisionError`
surfaces that collision instead of allowing the silent overwrite.

`.call` detects it by comparing corpora, not just keys: the corpus is the
first segment of `source_path` (`"charter/..."` vs `"code/..."`). An
existing row whose corpus differs from the incoming section is a genuine
collision, not a harmless re-run of the same upsert — which is why the
check only fires when both corpora are present AND they differ, never on
an ordinary repeat of the same corpus's own upsert.
