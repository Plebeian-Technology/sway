---
lat:
  mode: explanation
---

# Two admins, one LLM settings form

`useForm` fills itself from the page's props when it mounts.

The original submit sent the whole `admin_setting` hash on every save, so an out-of-date value in one admin's browser, for a setting they never touched, could get written back over whatever changed since their page loaded.

That was not a hypothetical race. `model` is part of what `TestimonyAttachmentClassification.for_verdict` matches on, so silently reverting `classification_model` meant paying for a full classification pass over every candidate attachment on the next run — and `updated_by_id` then named the admin who reverted it, so the record of who changed what actively misled the one person who might have noticed.

The controller drops keys that are missing from the request, which is the documented protection, but it only helps a client that leaves the key out. The web page — the only thing an admin actually uses — always sent both keys, so the drop-missing-keys guard never engaged for this form.

## Why POLLING_PROPS bundles the model values with who-changed-it-and-when

Every prop another admin can change travels together.

Every prop another admin can change travels together: the "who changed it and when" pair (`updated_by`, `updated_at`) travels with the model values, the offered `supported_models` list, and `available_openrouter_models`, so the caption and the "changed elsewhere" notice can never disagree about who changed what, and offered model additions or retirements made by another admin stay synchronized with the active selections and catalog add picker. The poll interval, 15000ms, matches the user-facing pages; this is a settings row, not a pipeline in flight, so it does not need the Bill Creator's tighter 5 seconds.

## The fix: a per-field baseline and an expected guard

`LlmSettings.tsx` captures a `baseline` in state when the page mounts (and refreshes it from the server's redirected props on save): the model, reasoning effort, and batch settings the page was rendered with.

`usePoll(15000, ...)` refreshes the props in the background so a `changedElsewhere` banner can tell the admin when another save has moved past that baseline, but nothing adopts the incoming values automatically — an admin with a selection open would silently lose their choice, and one without would see a control they are looking at move on its own.

On submit, `buildPayload` sends only the fields this admin actually changed, each paired with `expected: <the baseline value for that field>`. The controller (`Admin::LlmSettingsController`) checks each submitted field's `expected` against the column's *current* database value and refuses the whole save — with an inline error naming the field and its current value — if either mismatches.

The guard is per FIELD rather than one version number for the whole row on purpose: two admins changing *different* settings is the common case, and both saves must succeed. A row-level check would refuse the second one even though it touched nothing the first one changed.

This closes the gap the old key-omission guard never covered: the payload no longer carries a stale value for an untouched field at all, so there is nothing for that field to overwrite. `spec/system/admin_llm_settings_spec.rb` pins the fixed behavior under "two admins editing at once".

## What the "changed elsewhere" banner tells the admin

The banner arrives on its own within the poll interval.

It names the consequence for whichever state the admin is in: with a selection open, saving would be refused by the per-field `expected` guard; with none open, the controls below are simply showing the previous values.

## Why a client with no expected block conflicts with nothing

`stale_fields` finds which submitted settings changed since the page was rendered.

A client sending no `expected` block conflicts with nothing, on purpose — a JSON/bearer script has no page state to be stale against. Only the web page, where two humans can hold conflicting views of the row, sends it.

## Why the stale-conflict message is a refusal the admin can act on

`render_stale_conflict` names the field, the value actually stored, and what's left to do — a vague message was the original bug.

HTML and JSON get different sentences because the way out differs: a person is looking at the redirected page; a script has to re-fetch the row.

`stale_conflict_message` (the HTML sentence) doesn't ask for a browser refresh — the redirect to `admin_llm_settings_path` already swaps in fresh Inertia props before this message is drawn, and the page offers a button to load them. Both halves are pinned by `spec/requests/admin/llm_settings_spec.rb`.

`json_stale_conflict_message` (the JSON sentence) is the same refusal for a script, which has no page and no button. It names the column, because a JSON client can submit one field without the other, and it names the request that hands back the current row.

## Why a browser round trip, not just a model spec

Tuning the classifier without a deploy is the whole point of the LLM settings feature, so the browser round trip is what has to work — a passing model spec only proves the column exists.

The classification-model example also pins the independence the separate `classification_model` column exists for: changing it must leave `summarization_model` untouched.

## Test setup: the :sway_admin trait

`spec/system/admin_llm_settings_spec.rb` signs in with the `:sway_admin` factory trait, matching `spec/requests/admin/llm_settings_spec.rb`.

The trait handles `User::ADMIN_PHONES` itself, so the system spec no longer changes that constant in its own `around` block.

## Test setup: a second editor gets no admin trait on purpose

The "two admins editing at once" examples create the second editor as a plain `create(:user, is_registration_complete: true)`, deliberately not the `:sway_admin` trait.

That trait REPLACES `User::ADMIN_PHONES` with the new user's phone (`spec/factories/users.rb`), so creating a second admin mid-example strips admin rights from the admin already signed in, and `verify_is_sway_admin` sends the save back to the root page — which is exactly what the first draft of this spec produced. All that these examples need from the second editor is an id, to stand for the other editor.

## Test design: waiting for the thing the example is actually about

The non-admin denial example's real assertion is on the redirect target, not on wording.

The two `have_no_text` checks used to be the whole assertion, and they depend on the page's WORDING rather than on the guard: measured, not assumed — with `before_action :verify_is_sway_admin` deleted from the controller AND the heading renamed, a non-admin got the full admin page and the example still reported 1 example, 0 failures. That takes two separate edits, but renaming a heading is exactly the sort of change nobody re-checks an authorization spec over.

`verify_is_sway_admin` redirects browser clients to `root_path`, and `HomeController#index` sends a fully registered user on to `/legislators`. Landing there IS the refusal, and it does not depend on any words from the admin page, so the example asserts it outright first; only then does "LLM Settings is not on this page" mean anything. Put through the same simulated regression, this now fails with `expected "/admin/llm_settings" to equal "/legislators"`.

## Test design: no example for saving an invalid model

There is no example for saving a model outside the offered model list (`AdminSetting#offered_models_list`): the dropdown offers only allowed options, so the UI cannot produce a rejected save on its own.

The full round trip — rejection, then the errors rendered inline — is covered at the request level in `spec/requests/admin/llm_settings_spec.rb`, through `admin_setting_errors` and the errors carried in the session. Forcing a disallowed value from a system spec would mean either mutating the offered list mid-flight or hand-rolled fetch contortions — the kind of fight not worth having.
