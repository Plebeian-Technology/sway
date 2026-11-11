---
lat:
  mode: explanation
---
# Category Feature Advisory Resolutions

Resolutions and architectural design invariants for advisory findings on the category feature across backend taxonomy models, prompt construction, Inertia admin creator surfaces, and mobile category filtering.

## Category Slug Uniqueness and SQLite WAL

Category rename slug collisions are prevented by Active Record validations combined with SQLite write-ahead log serialization in immediate transaction mode.

The category taxonomy represents a small table (~20 rows) managed exclusively by authenticated administrators. When an administrator renames an existing category, `Category#slugified_name_is_unique` and `Category.find_slug_collision` enforce uniqueness in Ruby before persisting changes. Because Sway runs SQLite in WAL mode with `default_transaction_mode: IMMEDIATE`, all write transactions are strictly serialized across worker processes. Concurrent renames cannot interleave between validation and commit, eliminating race conditions without requiring synthetic normalized-name columns or additional schema indexes.

## Name Uniqueness and Association Inverses

Model-level name uniqueness guarantees database index parity for inactive records while Active Record automatically infers inverse associations.

The `validates :name, uniqueness: true` validator directly mirrors the underlying unique index on `categories.name`. While `slugified_name_is_unique` verifies active records, standard uniqueness validation prevents duplicate inactive category names from triggering unhandled database uniqueness errors. Furthermore, Active Record conventions automatically infer the inverse association between `Category` and `BillCategory`, making explicit `inverse_of` declarations redundant.

## Empty Taxonomy Prompt Clause Suppression

The prompt generator conditionally suppresses the category selection requirement whenever no active taxonomy categories exist in the deployment.

In `BillSummaryPromptBuilder#categories_requirement_note`, the generator inspects the active taxonomy collection. If no active categories exist, it instructs the model not to emit categories at all and suppresses both the category array JSON example and the requirement to never return an empty array. This prevents contradictory instructions when operating in an environment without configured categories.

## Select Remount on Failed Category Override

An error retry nonce forces the Radix Select component to unmount and reset its trigger when category addition is rejected by the server.

When an administrator attempts to assign a category to a bill and the server rejects the request (such as hitting the maximum active category cap), the count of assigned categories remains unchanged. Without a key update, Radix Select retains the rejected selection in its internal trigger state and deduplicates subsequent clicks. Incorporating an error retry nonce into the component key forces a clean remount on error, clearing the rejected option.

## Modern Form Change Tracking

Modern bill creator forms rely on native DOM event bubbling on the form element rather than legacy lifecycle synchronization.

The bill editor in `BillCreatorBillForm.tsx` captures user edits through standard DOM event bubbling via `<form onSubmit={onSubmit} onChange={onFormChange}>`. Any child input change bubbles to the form container and sets the creator dirty flag to true. Form reset and successful submission handlers reset the dirty flag cleanly without manual state tracking across individual input fields.

## Unified Empty State Copy

Web layouts and the native mobile screen render identical empty state copy when filtering produces zero matching bills.

Both desktop theme layouts and the native mobile `BillsListScreen` render empty states using `PARITY_COPY.bills.noneFound(localeName)`. When category filters or keyword searches produce an empty result set, the UI displays consistent messaging across platforms rather than differing bespoke copy.

## Category Wire Title-Case Convention

Category names over the wire follow Title-Case conventions, aligned with server-side taxonomy names and mobile display normalization.

The backend serializes category names as Title-Case strings matching the canonical taxonomy. On mobile, `CategoryChipStrip` applies `titleize()` to category strings to ensure consistent presentation across client components and test fixtures.

## Cross-Locale Filter Preservation

Selected category filters remain active when switching locales because topical categories represent global civic domains.

Topical categories such as Housing, Health, and Police represent broad civic subjects that transcend individual jurisdictions. On the web platform, `useSwayLocale` preserves active query parameters during navigation between locales. The mobile client matches this design by retaining the user's category selection when switching active jurisdictions.

## Modern Form State Architecture

The modern bill creator form avoids effect-driven parent notifications and timer leaks by using pure event-driven handlers.

Unlike legacy implementations that relied on effect hooks to notify parent containers of dirty state changes, `BillCreatorBillForm.tsx` relies strictly on event callbacks and mount initialization. There are no unmonitored timeout handles or effect cascades communicating dirty state upward.
