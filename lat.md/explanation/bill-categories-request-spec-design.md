---
lat:
  mode: explanation
---

# spec/requests/bills/categories_spec.rb design

`spec/requests/bills/categories_spec.rb` covers setting one bill's categories by hand: `POST /bills/:id/categories` (add) and `DELETE /bills/:id/categories/:category_id` (remove).

These paths sit under `/bills` rather than under `/admin`, but they still require a Sway admin, which the file's two shared examples check — otherwise anyone could change a bill's categories.

## Why re-adding an already-assigned category succeeds instead of erroring

With three active categories already on the bill, posting one it already has must succeed and change nothing, rather than fail with "Maximum 3".

The limit check has to stop early when the category is already attached. The UI cannot reach this path — its dropdown hides categories already assigned — but a direct API caller can, and sending the same request twice should be harmless.

## How a create failure's error message reaches the web caller

In a browser the controller calls `redirect_back(..., inertia: {errors: {category: ...}})`.

The message rides across the redirect in `session[:inertia_errors]`, and the next page render folds it into the shared `errors` prop — the same pattern as `spec/requests/admin/llm_settings_spec.rb`.
