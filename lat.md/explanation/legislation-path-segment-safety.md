---
lat:
  mode: explanation
---

# Legislation path segment safety

`Legislation::Paths` builds every on-disk path the legislation pipeline reads or writes.

Two rules keep those paths safe: every path segment is validated before it is used, and every bill-scoped path requires both a `sway_locale` name and an `external_id`.

## Why both pieces are required

A `Bill` is unique on `(external_id, sway_locale_id)` together (see `index_bills_on_external_id_and_sway_locale_id`), not on `external_id` alone.

Early builders took only `external_id`, so the database allowed two bills the filesystem could not tell apart: two cities' bill "25-0064" shared one `metadata.json` and one attachment set.

The damage from that gap is silent, not a crash: one bill's testimony gets assembled into another bill's `extracted_testimony` and fed to that other bill's positions prompt. Every builder in `Legislation::Paths` now takes both `external_id` and `sway_locale` and checks each one — never paste either value straight into a `Pathname`.

## Why the locale is a name, not an id

Paths use the `SwayLocale` name (for example `"baltimore-maryland-united_states"`), not `sway_locale_id`.

The id is an autoincrement key, so it names a different locale in every database and breaks silently when a production copy is restored into development. The name travels with the data and an operator can read it directly, unlike a bare autoincrement id.

## Segment validation

Both `external_id_segment!` and `sway_locale_segment!` (and their non-raising `_segment` siblings) check the candidate value against `Legislation::Paths::EXTERNAL_ID_PATTERN` before it becomes one path segment.

Both `external_id_segment!` and `sway_locale_segment!` (and their non-raising `_segment` siblings) check the candidate value against `Legislation::Paths::EXTERNAL_ID_PATTERN` before it becomes one path segment — deliberately excluding `/`, `\`, a leading `.`, NUL, whitespace, and wildcards. A `SwayLocale` name is generated from city, region, and country, so today it only ever contains letters, digits, hyphens, and underscores — the check exists because "today" is not a guarantee.

The raising form (`!`) is for callers inside a per-bill pipeline stage, where `RunLegislationPipelineJob#execute_bill_level_service` catches `Legislation::Paths::UnsafeExternalIdError` and fails only that one bill. The non-raising form is for admin panels and `Pipeline::ArtifactPresence`, which walk every bill in a locale and only ask "is there a file for this?" — raising there would take down a whole page over one unusable row. See [[docs/explanation/pipeline-unsafe-external-id-rescue.md|Why UnsafeExternalIdError is rescued in execute_bill_level_service]] for the full list of raising call sites and why `FetchBillsService` needs no rescue of its own.

`EXTERNAL_ID_PATTERN` is sized to cover what the three jurisdictions actually produce — Baltimore `NN-NNNN`, Maryland `HB1234`/`SB567`, Congress `hr815`/`S.J.Res.12` — plus `_` and `.` anywhere but the start, for room to grow. `external_id_segment!` does the same job as `FetchHearingsService#coerce_matter_id!`, guarding the same risk: an id read from `metadata.json` is operator-editable, so someone could smuggle extra path segments into it.

`UnsafeExternalIdError` is its own class, not `BillProcessingError`, because this module sits below the pipeline and must not depend on it. `UNSAFE_EXTERNAL_ID_ECHO_LENGTH` bounds how much of a rejected value the error message may echo back — an `external_id` can come from `metadata.json`, which an operator can edit, so it is untrusted with no length limit of its own.

## Vocabulary

Everything in this module calls the jurisdiction `sway_locale`, never `locale`, so nothing here reads as a Rails i18n locale.

## Why a leading/trailing whitespace is trimmed, not rejected

`external_id_segment!` trims surrounding whitespace before checking the pattern, rather than rejecting a value that has any.

Production holds two dormant ids that only fail the pattern by a leading TAB; trimming restores the id their owners meant without folding bills together. Rejecting a TAB instead would turn an admin "is there a file?" check into a server error for no security gain — a TAB is no way out of a directory. `Bill` trims the same way in a `before_validation` callback.

## Sanitizing an upstream file name (.upstream_file_name)

`.upstream_file_name` turns a file name an outside system handed us into one that is safe to use, or `nil` when nothing usable is left.

Legistar file names arrive inside JSON, already scrubbed to valid UTF-8 by `Legistar::Client` before parsing (so a mis-encoded title can't kill a whole run) — not by a bare `File.basename`. A NUL byte defeats that scrub: it IS valid UTF-8, and `JSON.parse` decodes its escape into a real one. `File.basename` then raises `ArgumentError`, not a `BillProcessingError`, failing the whole run — so `.upstream_file_name` deletes NUL bytes itself before calling `File.basename`.

`"."` and `".."` are refused as well. `File.basename` hands both straight back, and every caller joins the result onto a directory, so `".."` would name the parent of the folder the file belongs in.

The method assigns `value` to a new local (`text`) rather than using a `return nil unless value.is_a?(::String)` guard clause, even though the guard clause reads better and behaves the same at runtime: Steep does not narrow the parameter on that guard here — it keeps seeing "any object or nil" — while a new local does narrow. This was measured with a targeted check on this file; a small standalone example could not reproduce it, so it is something about this project's own signatures. Do not simplify this back to a guard clause.

## Why every builder takes the locale as a keyword

Every builder in this module takes the locale as a keyword argument, deliberately. The locale name and `external_id` are both short strings, so a positional pair could swap silently and still build a wrong path.

The locale segment always comes FIRST in the path, so one jurisdiction's files sit in one subtree. That makes an operator's "remove everything for this locale" a single directory removal.

## Why FetchBillsService.persist still validates before mkdir_p

`Pathname#join` does NOT resolve `..`, but `FileUtils.mkdir_p` does.

A `metadata[:external_id]` of `"../../../../rails/config/pwned"` would create a folder anywhere the `rails` user can write and drop attacker-influenced JSON into it, even though the joined `Pathname` string looks contained. `#persist` relies on both halves of the artifact path being cleaned first — the folder name by `Legislation::Paths.bill_artifact_dir`, the filename by `Legislation::Paths.upstream_file_name` — precisely because `mkdir_p` itself will not stop a `..` segment. `FetchBillsService`'s spec named "`#persist` — the `mkdir_p` + `File.write` seam" covers exactly this.
