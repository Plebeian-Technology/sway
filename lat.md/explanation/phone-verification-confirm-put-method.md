---
lat:
  mode: explanation
---

# Why the phone-verification hooks send requests the way they do

Why the phone-verification hooks call useHttp directly against PhoneVerificationController instead of a page navigation or method-override workaround, how CSRF is handled, and why a failed send shows a toast.

## Why useConfirmPhoneVerification sends a real PUT

`PhoneVerificationController#update` is set up as a normal Rails resource route (`resources :phone_verification, only: %i[create update]` in `config/routes.rb`, which generates `PUT /phone_verification/:id`).

`useHttp.put()` (`app/frontend/hooks/authentication/phone/useConfirmPhoneVerification.ts`) sends a real HTTP PUT request, so no method-override workaround (Rack::MethodOverride's `_method=put` trick) is needed. CSRF protection is handled automatically by Inertia's shared HTTP client.

## Why useSendPhoneVerification uses useHttp instead of a page visit

`PhoneVerificationController#create` expects `params.require(:phone_verification).permit(:phone, :code)` and returns `{ success: boolean }` as raw JSON.

`useHttp` (`app/frontend/hooks/authentication/phone/useSendPhoneVerification.ts`) sends the request through Inertia's shared HTTP client (CSRF protection handled automatically) without triggering a page navigation — so `Passkey.tsx`'s single-page state machine (its sequence of sign-in steps) stays intact.

## Why a failed send shows a toast

This mirrors a similar bug fixed one level down on the same screen: a failed send used to leave the panel sitting on the phone field with no code input and no explanation, because `console.error()` alone never reaches the user.

Every sibling auth error handler already ends with a toast (`useAddPasskey` does it twice, `useWebAuthnRegistration` and `useConfirmPhoneVerification` do it via `handleError`). The 429 branch runs before reaching this code, so there's no risk of showing two toasts.
