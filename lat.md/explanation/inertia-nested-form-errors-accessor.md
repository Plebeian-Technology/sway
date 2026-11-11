---
lat:
  mode: explanation
---

# Reading errors from a nested Inertia form

A few admin forms shape their submitted data as a nested hash.

A few admin forms shape their submitted data as a nested hash — `LlmSettings.tsx` sends `{ admin_setting: { summarization_model, classification_model } }` so Rails reads it back as `params[:admin_setting][...]`; `CategoryRow.tsx` does the same with `{ category: { name } }`. Both need to read validation errors back out of that same nested shape, and both read BOTH possible shapes instead of assuming just one.

`useForm`'s `FormDataErrors<TForm>` type is keyed by dotted paths (for example `"admin_setting.summarization_model"`). But `inertia_rails` stores whatever hash the controller passes to `redirect_to ..., inertia: {errors: {...}}` exactly as written — its redirect handling merges that hash into the flash without flattening the nesting. So the errors prop can actually arrive as `{ admin_setting: { summarization_model: "..." } }`, not as a dotted key.

Both `adminSettingError` (`LlmSettings.tsx`) and `categoryNameError` (`CategoryRow.tsx`) read both possibilities:

```ts
const flat = (errors as Record<string, string | undefined>)["admin_setting.summarization_model"];
const nested = (errors as { admin_setting?: { summarization_model?: string } }).admin_setting?.summarization_model;
return flat ?? nested;
```

`LlmSettings.tsx`'s `AdminSettingErrors` type is keyed per field, because the controller attributes the rejection to whichever column the allowlist actually refused — `form.errors` itself only knows about top-level field names from the form data shape, so a typed accessor narrows the nested `admin_setting` errors instead of relying on `form.errors`'s dotted, flattened keys.

An earlier version of `LlmSettings.tsx` bridged this with a single cast — `(form.errors as FormErrors).admin_setting` — which happens to be correct for today's `inertia_rails` version but would go silently wrong for any other. If the gem or the controller ever flattens that shape, a cast-only accessor starts returning `undefined`: the inline error under the offending field disappears with no type error and nothing failing, leaving an admin whose choice the allowlist refused staring at a form that looks unchanged. Checking both shapes keeps the accessor correct either way.
