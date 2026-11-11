---
lat:
  mode: explanation
---

# AddCategoryForm.tsx and CategoryRow.tsx

Why AddCategoryForm.tsx uses useForm while CategoryRow.tsx uses router.patch, and the scroll/refocus/disable/toast details in both

## Why AddCategoryForm.tsx uses useForm and CategoryRow.tsx uses router.patch

Uses `useForm` because the value sent IS the form's own state (a name typed in) — the one place `useForm` fits. Existing-row edits go through `router.patch` instead, as in `CategoryRow.tsx`.

`CategoryRow.tsx`'s own side of this: changes go through `router.patch`, NOT `useForm` — the name/active flag belong to the row, not a form. Same habit as `BillSchedule.tsx`. Also, `useForm().patch`'s options in Inertia React 3.3.0 drop `data`, so `{ data: {...} }` fails the type check and is silently ignored at runtime.

## Selectable text

Neither file adds `select-none` or `user-select:none`: in `AddCategoryForm.tsx`, text must stay selectable; in `CategoryRow.tsx`, category names and labels must stay selectable and copyable.

## No useEffect

`AddCategoryForm.tsx`: this is form state only, with no side effects.

`CategoryRow.tsx`: no `useEffect` or `useLayoutEffect` — the rename state lives up in `Categories.tsx`, which owns `editingId` and `renameDraft`, so this component only reads its props.

## Reading validation errors back out of the nested shape

Both components read the CategoriesController refusal out of `page.props.errors` (a visit's `onError` in `CategoryRow.tsx`.

Both components read the CategoriesController refusal out of `page.props.errors` (a visit's `onError` in `CategoryRow.tsx`, `form.errors` in `AddCategoryForm.tsx`), arriving either flat as `"category.name"` or nested as `{ category: { name } }}`. See [[docs/explanation/inertia-nested-form-errors-accessor.md|Reading errors from a nested Inertia form]] for the general pattern — `AddCategoryForm.tsx`'s `categoryNameError` and `CategoryRow.tsx`'s `categoryNameError` are both instances of it.

## Scrolling to the affected row

`AddCategoryForm.tsx`, on a successful create: the list is sorted by name, so the new row often lands below the visible part of the page. It finds the new row in the fresh props the redirect brought back and scrolls to it.

`CategoryRow.tsx`, on a successful rename: same reasoning — the table is sorted by name, so a rename can move the row off-screen — so it scrolls the renamed row back into view.

## Refocusing the add-category input after submit

`disabled={form.processing}` drops focus and never returns it.

`AddCategoryForm.tsx` refocuses the input in a `window.setTimeout(..., 0)` after a successful add, so adding several categories doesn't need re-clicking; one tick is needed because a disabled input can't take focus yet.

## Disabling the add-category input while the request is in flight

Switches the input off while the add is in flight, so a key pressed during the request is not thrown away by the `form.reset()` that runs on success.

## Keeping the submitted name across form.reset()

`AddCategoryForm.tsx` keeps the submitted name before `form.reset()` wipes it. It is used to find the new row and scroll to it. The controller trims whitespace off the name, so the comparison is against the trimmed value.

## Clearing the input on success

`useForm` state survives the Inertia visit, so without calling `form.reset()` the box still shows the added name and the operator may resubmit a duplicate.

## Toasting refused PATCH/DELETE requests in CategoryRow.tsx

`CategoriesController#update` refuses via `page.props.errors`, not `flash.alert` — with no `onError` the row sits stuck saying nothing. The rename handler toasts the error and stays in edit mode so the admin can retry.

Activate/deactivate can be refused too — e.g. a slug clash on reactivation. `toggleActive`'s `onError` toasts the failure instead of doing nothing, same as the rename case above.

## Delete confirmation copy

`handleDelete` is only shown on inactive rows; it runs against `active: false`, checked again server-side (see [[docs/explanation/admin-category-soft-delete-routing.md|Why admin category routes use a plural resource with a gated destroy]]). It also removes `bill_categories` links, so still-attached bills lose them — the confirmation dialog says so.
