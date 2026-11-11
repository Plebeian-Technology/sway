---
lat:
  mode: explanation
---

# Admin::CategoriesController design

Admin page for managing bill categories — the topic labels attached to bills. Admins can add a category, rename it (name only — the slug is frozen after creation, see [[docs/explanation/seed-category-slug-key.md|Why SeedCategory doesn't use Seedable]]), and deactivate or reactivate it, all live with no deploy.

## Why both create and update answer in two formats

Success and validation failures are both wrapped in `respond_to`, mirroring `Admin::LlmSettingsController#update`, so JSON/bearer-token callers get a JSON body instead of a 302 redirect.

## create: why the empty-name and punctuation-only checks come first

An empty name: the model's presence validation would produce "Category name is required." anyway — `create` returns that message immediately, so the slug check below cannot intercept a blank name with the wrong message.

A punctuation-only name (e.g. `"!!!"`) is not blank, but it slugifies to `""`. That trips the slug presence validation — yet `name_error_copy` only looks at `:name` errors, so the admin would see the generic "Category name is invalid." with no hint at the real cause. `create` catches the empty-slug case itself and says plainly that the name needs at least one letter or number.

## create: why the collision check runs in two directions

Reject when `slugify(name)` matches EITHER the slugified CURRENT name of an existing category, OR a frozen STORED slug (a since-renamed category still keeps its old stored slug).

The current-name check matters because `BillCategoryAssigner` keys its lookup on `slugify(current name)` (see [[docs/explanation/seed-category-slug-key.md|Why a collision is validated against at all]]); the stored-slug check matters because the DB's unique slug index would reject the row anyway. Doing both here shows the right active/deactivated message before the DB raises a misleading error. The model's `slugified_name_is_unique` validation and the slug index remain as backstops.

A CURRENT-name collision (the typed name slugifies the same as some row's current name) can suggest reactivation, because reactivating that row brings back exactly the name the admin just typed. A STORED-slug-only collision means a category was renamed away: its frozen slug still equals `slugify(typed)` but its current name is different. Even if that category is deactivated, "reactivate it instead" would not help — reactivating restores its renamed name, not the typed one — so this case always uses the generic name-taken message.

## create: why RecordNotUnique gets its own rescue

Two creates racing on the same name can both pass the pre-check; the loser then trips the DB's unique slug index, which raises `RecordNotUnique` (not `RecordInvalid`). The rescue shows the same name-taken message instead of a 500.

## update: why the rename collision check also covers current names

Rejects a rename whose slugified name collides with another category's slugified CURRENT name.

`BillCategoryAssigner` builds its lookup map with `index_by { |c| Category.slugify(c.name) }`; if two categories slugify to the same key, `index_by` silently keeps only one of them, and LLM category assignment becomes unpredictable. Checking stored slugs alone is not enough — a rename can make `slugify(new_name)` collide with `slugify(other.name)` even while the stored slugs stay different. It uses the same `Category.find_slug_collision` as `create` and the model validation, so create / rename / reactivate all apply one rule and cannot drift apart again.

The whitespace-stripped name is saved, matching what `create` does. Without this, `category.update!(attrs)` would save the raw un-stripped `attrs[:name]`, and `update` would behave differently from `create`.

## update: why reactivation is blocked against the per-bill cap

Blocks a reactivation that would push a bill over the 3-active-category cap.

The cap counts only ACTIVE categories per bill, so a bill can hold 3 active plus this one inactive; reactivating would make 4 (`Bill#to_builder` has no ceiling). It rejects when any bill carrying this category already has 3+ OTHER active categories — trim those first.

`reactivating?` is true only when this PATCH flips `active` from false to true. A rename-only patch (no `:active` key, and `cast(nil)` is falsy) or a true→true no-op is NOT a reactivation. `ActiveModel::Type::Boolean.cast` accepts both the JSON boolean `true` and the form strings `"true"`/`"1"`.

`reactivation_would_exceed_cap?` asks whether any bill carrying this (currently inactive) category already holds 3 or more OTHER active categories. The category is still inactive at this point, so the active-count subquery excludes it by definition — its COUNT is the bill's OTHER active categories. `bills_at_active_cap` is extracted into its own method so tests can assert the cap it enforces: the threshold sits inside a raw Arel SQL fragment — the one form no behavioural spec can read back — so of the places that use the cap, this one was the most able to drift and the least able to show it.

## destroy: two-step delete and why it skips the re-arm

See [[docs/explanation/admin-category-soft-delete-routing.md|Why admin category routes use a plural resource with a gated destroy]] for why deletion is a deliberate two-step (deactivate, then delete).

`destroy` deliberately skips `rearm_unmatched_categorization!` — the active-only gate above means it only ever deletes an already-inactive category, so the active set the "unmatched" stamps were measured against hasn't changed; re-arming would cost a Claude call per stamped bill for no new matches. If that gate is ever relaxed, `categories_spec`'s "leaves the stamp alone" example will catch it — that's the signal to start re-arming.

## Why the re-arm is global rather than diffed against what changed

See [[docs/explanation/backfill-bill-categories-scope.md|Stamping a deterministic no-match]] for what the `categories_unmatched_at` stamp means and why clearing it re-opens a bill for categorization.

`rearm_unmatched_categorization!` is deliberately global rather than diffed against what changed: figuring out which bills a given change could newly match is the LLM's job, not a query's, and clearing too broadly only costs one retried call per bill.

## Minor extractions

`index_props`'s bill counts come from one grouped query (`BillCategory.group(:category_id).count`), so there is no per-category query (no N+1).

`notice_for` uses ActiveRecord dirty-tracking to tell a rename apart from an active toggle — the UI only ever sends one at a time, so checking `saved_change_to_name?` before `saved_change_to_active?` is enough to label the change correctly.

`name_error_copy` never passes `e.message` (the raw "Validation failed: Name has already been taken") through to the UI — it maps validation errors to the exact wording the UI spec requires. A derived-slug collision (e.g. matching the frozen stored slug of a since-renamed category) surfaces as a `:slug` `:taken` error, not `:name` — it is reported as a name clash rather than the generic "invalid" message.

## Why the validation-copy examples request JSON

`spec/requests/admin/categories_spec.rb`'s error-message-wording examples ask for JSON, so the 422 response body can be read directly.

They assert that `name_error_copy`'s mapped wording — not Rails' own "Validation failed: ..." sentence — is what reaches a person.

## Why it inherits ApplicationController directly, and the mass-assignment guard

There is no `Admin::BaseController`.

There is no `Admin::BaseController` — every `Admin::*` controller inherits `ApplicationController` directly, so each one carries its own `before_action :verify_is_sway_admin`, its own entry in `lib/tasks/sway_lint.rake`'s `admin_controllers` array, and its own listing in CLAUDE.md's authoritative admin-controller list (see "Admin Endpoints" in CLAUDE.md). Dropping the `before_action` fails `rake sway:lint:admin_guards` loudly — that is the gate's purpose. Dropping the `sway_lint.rake` entry is the silent failure mode: the lint gate has nothing left to check for this controller. The CLAUDE.md listing is documentation only; nothing enforces it.

Params permit only `:name` and `:active`; `:id`, `:slug`, and `:created_at` are never accepted from the request — the slug is always derived server-side via `Category.slugify`.

## Categories.tsx, the frontend page

`app/frontend/pages/admin/Categories.tsx` is the `/admin/categories` page.

An admin can see every category with a live count of its bills, add one, rename one (the name only — the slug never changes), and turn one off or back on while the app is running, with no deploy. It uses the same page shell as `LlmSettings.tsx`: `space-y-6`, `max-w-4xl`, `Card` structure, no `useEffect`.

Flash messages are shown ONCE, globally, by `registerFlashToasts` — a Toaster mounted in `App.tsx` that drops duplicates. This page used to draw its own banners as well, saying the same thing twice, so they were removed.

Layout: the categories table is the main event and sits first, in the top Card. The "Add category" form comes second, below it in its own Card.

The rename state (`editingId` and `renameDraft`) is held in `Categories.tsx` rather than inside `CategoryRow`, so `CategoryRow` takes only props and needs no `useEffect` or `useLayoutEffect`. `editingId` also means only one row can be renamed at a time.

Two style rules: never use `select-none` or `user-select:none` — all text stays selectable. And no `useEffect` — the inline rename is driven purely by state.
