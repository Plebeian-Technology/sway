# Objective

Implement continuous, real-time score updates using Inertia 2.0's `usePoll` and ActionCable signals, ensuring consistency across Legislators, Bill, BillOfTheWeek, and Bills pages.

# Key Files & Context

- `app/controllers/legislators_controller.rb`: Needs to include scores in Inertia props.
- `app/controllers/bills_controller.rb`: Already includes scores, but needs to be optimized for partial reloads.
- `app/services/score_updater_service.rb`: Target for ActionCable broadcasts.
- `app/frontend/pages/`: Target for `usePoll` and ActionCable listeners.
- `app/frontend/hooks/usePollBillOnUserVote.ts`: To be replaced by `usePoll`.

# Implementation Steps

## 1. Backend: ActionCable Broadcasting

- **Create Channel:** Create a `ScoreChannel` to stream updates.
- **Broadcasting:** In `ScoreUpdaterService`, add a broadcast signal at the end of the `run` method:
  `ActionCable.server.broadcast("scores_#{user.id}", { action: "refresh_scores" })`.

## 2. Frontend: Real-Time Signal Handling

- **Set Up Consumer:** Initialize the ActionCable consumer in the frontend.
- **Signal Listener:** Implement a listener in the main pages that calls `router.reload({ only: ['bill_score', 'legislators'], preserveScroll: true })` when the "refresh_scores" signal is received.

## 3. Frontend: Inertia 2.0 Polling

- **Apply `usePoll`:** Add `usePoll(15000, { only: ['bill_score', 'legislators'] })` to the main pages (`Bill`, `Bills`, `Legislators`).
- **Throttling:** This provides a fallback for updates from other users even if the WebSocket connection is interrupted.

## 4. Inertia Props Optimization

- **Legislators Props:** Update `LegislatorsController#index` to include the `user_legislator_score` in the legislator objects sent as props.
- **Remove Axios Fetching:** Refactor `BillChartsContainer` and `LegislatorCard` to read scores directly from page props (via `usePage().props`) instead of using `useAxiosGet`. This follows the "no initial data fetch" best practice.

## 5. Controller Fixes

- **Redirection:** Update `UserVotesController#create` to honor the `redirect_to` parameter or use `redirect_back`, ensuring users stay on their current page with fresh props.

# Verification & Testing

- **Real-Time Test:** Verify that voting immediately triggers a partial reload in other sessions via ActionCable.
- **Polling Fallback:** Verify that scores still update every 15 seconds even if the WebSocket is disconnected.
- **Network Efficiency:** Confirm that reloads are "partial" and only fetch the specific props needed for scores.
