# Mobile membership state

The mobile membership detail screen owns the displayed membership response. Position mutations reload that response; proposal recovery retains the successful save while retrying the read.

## Single authoritative state boundary

The [[mobile/src/screens/MembershipDetailScreen.tsx]] screen displays the response loaded by [[mobile/src/hooks/useMembership.ts#useMembership]].

[[mobile/src/components/PendingChangesList.tsx#PendingChangesList]] receives pending changes from the screen and refreshes that response after approval or rejection, holding controls busy until the reload settles.
[[mobile/src/components/NewPositionModal.tsx#NewPositionModal]] disables eager membership loading in [[mobile/src/hooks/useOrganizationPositions.ts#useOrganizationPositions]] with `{ enabled: false }`, ensuring that proposing a position triggers only the screen's authoritative reload.

While [[mobile/src/components/NewPositionModal.tsx#NewPositionModal]] remains open, saved state presents a retry banner that refreshes membership without re-posting the position. On the parent screen, [[mobile/src/screens/MembershipDetailScreen.tsx]], failed reloads display cached data alongside a reload error banner and retry button.

[[mobile/src/components/NewPositionModal.tsx#NewPositionModal]] blocks both Close and native dismissal while a proposal POST or its authoritative reload is pending. The transaction retains its submission lock until settlement, preventing overlapping proposals and an earlier completion from clearing a newer draft. Successful reload closes and resets the form; failure leaves it open with dismissal available and the appropriate retry state.

In [[mobile/src/components/PendingChangesList.tsx#PendingChangesList]], a failed reload after position rejection triggers screen-level reload recovery without popping an alert that the rejection failed. The screen presents the reload error banner while retaining saved state, allowing retry without repeating the deletion.

[[mobile/src/hooks/useInviteAccept.ts#useInviteAccept]] distinguishes a failed invitation mutation from a failed read after the mutation succeeds. It waits for the server before refreshing; it performs no optimistic invitation removal or restoration. Its error state describes failed mutations, while [[mobile/src/hooks/useInviteAccept.ts#InviteRefreshError]] identifies failed refreshes after saved mutations.

[[mobile/src/screens/MembershipDetailScreen.tsx]] retains its acceptance guard after a saved invitation's refresh fails. The screen offers membership reload recovery without reporting acceptance failure or repeating the saved POST. A failed acceptance POST leaves explicit acceptance retry available.

The adversarial screen tests hold initial and final membership reads and resolve them inside awaited `act` scopes before checking rendered state. A request count alone does not show that React has applied the response.

## Hidden modal query suppression

Modal dialogs that remain unrendered or hidden during normal tab navigation do not execute eager queries on mount.

Deferred query execution prevents duplicate network traffic for bills and positions while the user navigates between positions and pending changes tabs.
