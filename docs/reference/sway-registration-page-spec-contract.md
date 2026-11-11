---
mode: reference
summary: "The states SwayRegistration.tsx can show and the exact data-testid values its browser specs depend on."
status: agent-extracted
related: []
---

# SwayRegistration page spec contract

`app/frontend/pages/SwayRegistration.tsx` is the registration page in the
current UI, moved over from the old V1 code. `pageResolver.ts`
loads this file directly; there is no falling back to a V1 page any more,
because the resolver throws when a page is missing.

## States this page can show

| State | Condition |
| --- | --- |
| `processing` | a background job is running; the page asks the server every 3 seconds for fresh `user` and `processing` values |
| `failed` | `registration_status` is `"failed"` |
| `missing` | no user id, which should not normally happen; shows a dead-end card |
| default | the address form |

## Browser test contract

The browser tests look for these exact things — do not change them without
updating the specs:

| Element | Selector / content |
| --- | --- |
| Processing state | `[data-testid='registration-processing']` containing "Finding your representatives" |
| Processing message | `[data-testid='registration-processing-message']` |
| Error state | `[data-testid='registration-error']` containing "Registration failed" |
| Cancel button | `[data-testid='btn-cancel-registration']` |
| Submit button | `[data-testid='btn-submit-registration']` |

## Migration note

`AddressAutocomplete` now belongs to the current UI, at
`app/frontend/components/user/AddressAutocomplete.tsx`, and takes the
Inertia `useForm` object directly, so the old `FormContext.Provider` bridge
and the `RegistrationFields` wrapper are gone.
