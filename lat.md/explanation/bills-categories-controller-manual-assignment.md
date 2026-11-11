---
lat:
  mode: explanation
---

# Bills::CategoriesController: manual per-bill category assignment

Lets an admin set one bill's categories by hand, separate from the categories the summarizer picks automatically — writes straight to the `bill_categories` join table.

The page updates right away via `router.reload` after each change.

## Why the count-and-insert is inside with_lock

Counting and inserting inside one row lock matters because without it, two concurrent requests could both read "only 2 so far" and both insert, leaving

4. `with_lock` opens a `BEGIN IMMEDIATE` transaction (SQLite WAL mode), so

the re-count and insert happen as one indivisible step.

The limit counts only switched-on categories, matching `BillCategoryAssigner` — a category an admin later switched off stays on the bill but doesn't use up a slot, so the two limits can't drift apart. Both mean the same thing: at most 3 switched-on categories.

## Why an already-attached category is a no-op success

If the category is already on the bill, `#create` treats it as a no-op success rather than an error, so re-sending the same request on a bill already at 3 categories doesn't fail with a misleading limit error.

This only matters for a direct route hit; the UI's dropdown already hides categories the bill has.

## Why destroy matches by id only, not active:

`#destroy` matches by `bill_id` + `category_id` only (not `active:`), so a category switched off after attaching can still be removed.

## Security notes

`#create` looks up the category with `Category.where(active: true).find_by` — a miss (unknown or switched-off id) redirects with a 422, never a bare 404 or `RecordNotFound`.

The three-categories-per-bill limit is enforced server-side, not trusted to the client.
