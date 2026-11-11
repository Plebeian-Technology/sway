---
mode: explanation
summary: "Why Admin::LlmSettingsController locks the singleton row for its guarded write, shapes its dual-format responses the way it does, maps validation errors to fields, and redacts phone numbers from the provenance display"
status: agent-extracted
related: [docs/explanation/admin-llm-settings-singleton-route.md, docs/explanation/admin-llm-settings-stale-write-race.md, docs/explanation/admin-setting-model-list.md]
---

# `Admin::LlmSettingsController` design

## The admin-namespace convention, and the mass-assignment guard

`Admin::LlmSettingsController` is the controller that introduced the
`Admin::*` namespace. Like every controller in it, there is no
`Admin::BaseController` — it inherits `ApplicationController` directly, so
it carries its own `before_action :verify_is_sway_admin` and its own entry
in `lib/tasks/sway_lint.rake`'s `admin_controllers` array (see [the same
convention on `Admin::CategoriesController`](admin-categories-controller-design.md)
for what dropping each of those does).

`permit` whitelists only `summarization_model` and `classification_model`
from `params[:admin_setting]`. `updated_by_id` is never accepted from the
request body — it is set server-side from `current_user.id` inside
`apply_submitted_models`.

## Why labels live off the model

`SUPPORTED_MODEL_LABELS` keeps the friendly labels for the Claude tiers off
the `AdminSetting` model, so wording can change without a migration. Keys
must stay in lockstep with `AdminSetting::SUPPORTED_MODELS` — the lint uses
that list as the allowlist.

## `UNCHANGED_MESSAGE`

A submit that changes nothing is told this, instead of the generic "Model
updated." — a body with no model fields would otherwise still write
`updated_by_id`/`updated_at`, recording a change that never happened.

## Why `#update`'s response shapes differ by client

Inertia/HTML clients get a redirect-after-post with `flash[:notice]` (or
Inertia errors on rejection); JSON/bearer clients (scripts, a future mobile
admin client) get a JSON body instead, since a 303 redirect is useless to
them — mirroring the admin gate's dual-format response elsewhere in this
codebase. The success JSON exposes only
`summarization_model` + `classification_model` + `updated_by_id` +
`updated_at`, not the full row — the caller has no use for the id or other
timestamps.

## Why `apply_submitted_models` locks the whole read-decide-write

It reads, decides, and writes inside ONE locked transaction, so the guard
against a stale overwrite can't be raced by a second admin's PATCH landing
in the gap between a separate check and write.

`#with_lock` reloads the row inside the transaction (the pattern this app
uses elsewhere for a guarded write: `PipelineRunStage#mark_bill_completed!`,
`PasteSummaryService`, `UserOrganizationMembership`,
`BillCategoryAssigner`) — under SQLite's WAL mode that's `BEGIN IMMEDIATE`,
a true one-writer-at-a-time barrier.

A submit that moves no value writes nothing (the `:unchanged` branch skips
`update!`) rather than stamping `updated_by_id`/`updated_at` for a change
that never happened.

`apply_submitted_models`'s second return slot is always "which submitted
fields moved since the page rendered" — a Hash, never nil, since only the
`:stale` arm reads it and `#render_stale_conflict` expects a non-nilable
parameter.

## Why `render_settings` sends the same JSON body for both outcomes

The success response is shared by `:updated` and `:unchanged`. The JSON
body is identical either way — a script gets the same answer; only the
human-facing notice text distinguishes "changed" from "nothing to change".

## Mapping validation errors to fields

`rejected_model_errors` attaches each rejection to the field that caused it
— with two selects on the page, an unqualified error would
print under the wrong field.

When the only error is on `:base` (the `enforce_singleton` validation), the
model WAS recognized, so "choose from the list" would be false — this
carries the record's own error text instead.

The `:base` fallback still keys on `:summarization_model` because
`ModelSelectField` renders errors by column name and would silently drop a
`:base` key otherwise.

`json_rejection_message` is the JSON twin: one sentence instead of a
per-field Hash, since there's no field to attach to, but the message is
chosen the same way — it avoids the false "choose from the list" when the
error is really on `:base`.

## Why `rejected_model_errors`'s per-column attribution has its own regression test

An earlier version hard-coded the rejection to always blame
`summarization_model`. Every request, system, and model spec still passed,
because the summarization side was covered — an admin whose classification
choice was refused just saw the error under the wrong field, next to a
summarization value that was fine. Per-column attribution needs its own
test on the classification side specifically, not only summarization, or a
regression like this one passes the suite again.

The `:base`-only failure (neither column is individually invalid) used to
fall back to the same "Model not recognized. Choose from the list." wording,
which was actively wrong: the model WAS recognized, and picking a different
one — the only thing that message invites — cannot fix a `:base` validation
failure. The message is still attached to `summarization_model` because
that is the only field `ModelSelectField` can show it under; what changed is
that the words became true.

## Why `current_summarization_model`/`current_classification_model` are named per setting

`show_props` names these per setting rather than a bare `current_model` —
with two selects on the page, an unqualified name is the kind of ambiguity
that produces a wrong-field bug.

## `LlmSettings.tsx`, the frontend page

The admin page for choosing which Claude models run the bill summarization
job and the testimony attachment classifier. It is a page of
its own, not nested inside a hub.

The form data is shaped as `{ admin_setting: { summarization_model,
classification_model } }` so Rails reads it back as
`params[:admin_setting][...]`. That matches what `ApiKeys.tsx` already does
and what the controller's `params.require(:admin_setting).permit(...)`
expects.

NO `useEffect` anywhere: this page is form state plus Inertia partial
reloads. A `usePoll` was added so the row updates itself when the OTHER
admin sharing this page saves. Everything that follows from that — whether
the props have moved past the values this page based its save on, and what
that means for saving — is worked out during render. The only things that
change state are the Save button and the notice's own "load the current
models" (see [the stale-write race this baseline mechanism
replaced](admin-llm-settings-stale-write-race.md)).

The Inertia validation-errors prop is filled in by the controller when
`ActiveRecord::RecordInvalid` is raised (the allowlist rejected the
choice), via the `redirect_to ..., inertia: {errors: {...}}` option.
Inline error text appears below the offending Select.

The provenance badge ("is this the seeded default or an operator
override?") was moved up here from beside the summarization label: provenance is recorded once for the whole row (a single
`updated_by_id`), so pinning the badge to one of the two fields would have
implied it described only that field.

## Why the provenance display redacts the phone number

`provenance_display_name` never exposes `User#phone` through Inertia
props — it's redacted from logs by
`config/initializers/filter_parameter_logging.rb`, and admin-to-admin
leakage via Sentry's prop capture is still worth closing. It falls back to
a neutral label when `full_name` is blank; not worth leaking a phone
number to tell two admins apart.
