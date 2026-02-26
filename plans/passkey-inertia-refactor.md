# Objective

Fix critical WebAuthn implementation bugs and refactor the Passkey authentication flow to adhere to Inertia.js best practices and Material UI standards.

# Key Files & Context

- `app/models/user.rb`: Fix `webauthn_id` persistence by removing `attr_accessor` and ensuring generation.
- `app/controllers/users/webauthn/registration_controller.rb`: Add `exclude_credentials` to registration ceremony.
- `app/frontend/pages/Passkey.tsx`: Migrate from Bootstrap to Material UI and refactor state management.
- `app/frontend/hooks/authentication/useWebAuthnRegistration.ts`: Refactor to better align with Inertia patterns if feasible.
- `app/frontend/hooks/authentication/useWebAuthnAuthentication.ts`: Refactor to better align with Inertia patterns if feasible.

# Implementation Steps

## 1. Fix User Model Attribute Persistence

- Remove `attr_accessor :webauthn_id` from `app/models/user.rb` to allow database persistence.
- Ensure `after_initialize` correctly sets the ID for new or existing users without one.

## 2. Enhance Registration Ceremony Security

- Update `RegistrationController#create` to include `exclude_credentials` by mapping the user's existing passkey `external_id`s.

## 3. Migrate Frontend to Material UI and Inertia Patterns

- Refactor `Passkey.tsx`:
    - Replace `react-bootstrap` components with `@mui/material` components (`Box`, `Typography`, `TextField`, `Button`, `Fade`, `Grid`).
    - Use Inertia's `usePage().props` and query parameters to manage "Confirming Phone" state instead of local `useState`.
    - Employ Inertia's `useForm` hook for handling phone verification and WebAuthn callback submissions.
    - Ensure styling matches the project's Material UI conventions.

## 4. Refactor WebAuthn Hooks (Optional but Recommended)

- Adapt `useWebAuthnRegistration` and `useWebAuthnAuthentication` to work seamlessly with Inertia's `useForm` and redirect-based flow where possible.

# Verification & Testing

- Verify that `webauthn_id` is persisted in the database after user creation/initialization.
- Test the registration flow with an existing passkey to ensure `exclude_credentials` prevents duplicates.
- Manually verify the UI on the Passkey page for correct Material UI rendering and responsiveness.
- Ensure that the "Confirming Phone" state is correctly reflected in the URL query parameters and persists across page reloads.
