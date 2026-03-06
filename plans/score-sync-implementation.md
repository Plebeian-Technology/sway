# Score Synchronization Implementation

This document details the implementation of real-time score updates across the Sway platform, replacing the previous manual Axios polling with an idiomatic Inertia 2.0 and ActionCable hybrid system.

## Objective

Ensure that bill and legislator scores remain synchronized across all sessions in real-time while adhering to Inertia best practices (prop-driven UI, no initial `useEffect` data fetching).

## Architecture

### 1. Backend: Signal Broadcasting

- **ActionCable Channel:** A `ScoreChannel` was created to provide a dedicated stream for each user (`scores_#{user.id}`).
- **Service Integration:** The `ScoreUpdaterService` now broadcasts a `refresh_scores` signal to this channel immediately after scores are recalculated. This provides a "push" notification to the client that new data is available.

### 2. Frontend: Hybrid Sync System

The system uses two complementary mechanisms to keep data fresh:

- **Signal-Based Reload (Push):**
    - A custom `useScoreSubscription` hook manages the ActionCable connection.
    - When a `refresh_scores` signal is received, it triggers a **Partial Inertia Reload** using `router.reload({ only: [...] })`.
    - This is the primary driver for a "live" feel when the user casts a vote.

- **Inertia 2.0 Polling (Safety Net):**
    - The `usePoll(15000, { only: [...] })` hook is active on all core pages.
    - This serves as a background fallback, ensuring that updates from other users are eventually caught even if the WebSocket connection is interrupted or missed.

### 3. Data Flow Optimization

- **Eliminated Disjointed Fetches:** Removed `useAxiosGet` calls from sub-components (`LegislatorCard`, `BillChartsContainer`).
- **Consolidated Props:** All score data is now passed through the main Inertia page props.
    - `LegislatorsController` was updated to include `user_legislator_score` within the `legislators` array.
    - `BillsController` ensures scores are present in the `bills` and `bill_score` props.
- **Redirection Logic:** `UserVotesController` now honors the `redirect_to` parameter, allowing the UI to "stay put" and simply receive updated props after a vote is cast.

## Key Files

- `app/channels/score_channel.rb`: Server-side WebSocket definition.
- `app/frontend/channels/consumer.ts`: Frontend ActionCable entry point.
- `app/frontend/hooks/useScoreSubscription.ts`: Logic for handling refresh signals.
- `app/services/score_updater_service.rb`: Trigger for broadcasts.
- `app/frontend/pages/`: Pages implementing `usePoll` and `useScoreSubscription`.

## Best Practice Compliance

- **No `useEffect` for Data:** Initial data and updates are strictly prop-driven.
- **Partial Reloads:** Network overhead is minimized by fetching only specific props (`bill_score`, `legislators`, etc.) during sync events.
- **Scroll Preservation:** All sync reloads use `preserveScroll: true` to prevent UI jumping.
