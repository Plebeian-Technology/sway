# Plan: Registration Flow Refactor & Race Condition Resolution

## Background & Goal

The `Plebeian-Technology/sway-private` repository had architectural race conditions in its registration flow. Users were being marked as "registration complete" before background data (legislator assignments) was fully processed, especially for regional locales that require external API calls (e.g., OpenStates). This led to UI inconsistencies and errors in the React Native/Inertia hybrid infrastructure.

The goal was to refactor the registration flow to use a robust state machine, introduce a "processing" state for async operations, and ensure the frontend correctly handles these states.

## Architectural Changes

### 1. State Machine Implementation

We integrated `state_machines-activerecord` to manage the `User#registration_status`.

- **States**: `pending` (initial), `processing`, `completed`, `failed`.
- **Transitions**:
    - `start_processing`: `pending` -> `processing`
    - `complete`: `pending`/`processing`/`completed` -> `completed`
    - `mark_failed`: `processing` -> `failed`
- **Hook**: An `after_transition` hook on the `complete` event updates the legacy `is_registration_complete` boolean for backward compatibility.

### 2. Service Refactoring (`SwayRegistrationService`)

The service was updated to accept an `async:` parameter (defaulting to `true`).

- If `async: true` and the locale is `regional?`, the user transitions to `:processing` and a `SwayRegistrationJob` is enqueued.
- If `async: false` (run from the job), the service performs the actual data fetching and legislator assignment.
- Transitions to `:completed` only occur after data is successfully persisted.

### 3. Background Processing (`SwayRegistrationJob`)

A new job handles the heavy lifting for regional registration. It executes the service with `async: false` and manages the user's state transitions (`complete!` or `mark_failed!`).

### 4. Controller Updates (`SwayRegistrationController`)

- **Index**: Detects the `processing` state and passes a `processing: true` prop to the Inertia frontend.
- **Create**: Initiates the async flow and redirects to the index (polling) if background work is needed.

## Implementation Details

### Files Modified:

- `Gemfile`: Added `state_machines-activerecord`.
- `db/migrate/20260225023350_add_registration_status_to_users.rb`: Added `registration_status` column.
- `app/models/user.rb`: Configured the state machine and updated `to_builder`.
- `app/services/sway_registration_service.rb`: Refactored to support async/sync logic.
- `app/jobs/sway_registration_job.rb`: Created for async processing.
- `app/controllers/sway_registration_controller.rb`: Updated flow handling.
- `app/controllers/application_controller.rb`: Updated auth logic to use state machine events.

## Verification

- **Automated Tests**: `spec/services/sway_registration_spec.rb` verifies the state transitions and async enqueuing.
- **Manual Verification**: Verified that `is_registration_complete` is only set after the `complete` event.
- **Race Condition Check**: Confirmed that users in `processing` state are not redirected to the legislators dashboard until the job finishes.

## Next Steps

- **Mocking External APIs**: Stabilize CI by mocking OpenStates/Senate/MGA API calls in tests.
- **Frontend Polling**: Ensure the React Native consumer implements polling when the `processing: true` prop is received.
