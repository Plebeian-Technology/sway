---
lat:
  mode: explanation
---

# Mobile Jest test notes

Mobile test suites isolate screen rendering and asynchronous device hooks to maintain deterministic test execution across parallel test lanes.

The native test suite stubs React Native device integration and asynchronous storage to ensure stable assertions without relying on real device APIs.

## Notification preferences hook mock shape

The test suite mocks `useNotificationPrefs` to mirror the precise contract returned by the production hook.

[[mobile/__tests__/screens/NotificationPrefsScreen.test.tsx]] stubs preference queries and toggle callbacks using `{ prefs, loading, error, toggle, refresh }`. Omitting intermediate internal states such as `pending` reflects the production hook interface and prevents tests from coupling to unexported internals.

## Flushing push permission state updates with act

Resolving push permission promises inside `act` flushes state updates immediately through the microtask queue rather than relying on timer-based polling.

Under parallel test gates with heavy host contention, `waitFor` timeout thresholds can expire before timer callbacks fire. Wrapping resolution in `act` within [[mobile/__tests__/screens/NotificationPrefsScreen.test.tsx]] drains React Native microtasks synchronously, preventing gate-specific timing flakes.

## Asynchronous assertions for organization defaults card

Assertions on organization default settings wait for specific rendered text elements rather than the parent card container.

In [[mobile/__tests__/screens/NotificationPrefsScreen.test.tsx]], the card container mounts immediately while preference defaults load asynchronously. Awaiting rendered text via `findByText` ensures tests wait for API resolution rather than asserting against an unpopulated initial state.

## App test supplies the completed profile contract

The app shell test supplies an authenticated session and a server-shaped user profile.

[[mobile/__tests__/App.test.tsx]] sets `is_registration_complete: true` because [[mobile/src/navigation/RootNavigator.tsx]] requires the authoritative completion boolean before mounting the app drawer. A saved address and `registration_status: "completed"` alone do not satisfy that gate.

## App test has a bounded navigator render

The full app navigation tree needs a longer per-example render bound under parallel mobile test load.

[[mobile/__tests__/App.test.tsx]] gives the end-to-end app-shell render its own timeout, keeping normal focused tests fast while avoiding false failures when the host schedules several Jest suites together.

## App test never reaches the network

The app shell test replaces `fetch` with a call that fails at once, so rendering the whole app sends nothing to the production API.

The real app tree starts a bootstrap request, a push-token request and a reachability probe on every render. Left on the real `fetch`, each one opens a socket to the production host and arms its own 10 to 15 second abort timer, and the Jest worker running [[mobile/__tests__/App.test.tsx]] cannot exit until they settle. A Jest run then ends with "A worker process has failed to exit gracefully". A failed request settles the call, so `apiClient` and the reachability hook clear their timers, and the test then drives the app as if the device were offline.

## Retry controls settle after mutation failure

Mutation retry tests wait for the action control to become enabled before pressing it again.

[[mobile/src/components/PendingChangesList.tsx#PendingChangesList]] reports a rejected deletion before its final busy-state cleanup. The alert therefore precedes the rendered retry control's readiness. [[mobile/__tests__/screens/MembershipDetailAdversarial.test.tsx]] waits for the enabled Reject control and the confirmation sheet, while retaining the failed-delete, no-refresh and successful-retry assertions.

A rendered enabled control is not yet a pressable one. React Native's `Pressable` copies its `disabled` prop into its press handling in a passive effect, which runs in a later scheduler task than the commit. `waitFor` polls outside `act`, so it can observe the enabled render while that effect is still pending, and a press in that gap is silently ignored. A longer timeout cannot recover the lost press. Any press whose settling precedes another press on a control it disabled therefore goes through `fireEventAsync`, whose awaited `act` flushes the passive effects before the test continues.

## BroadsideTabStrip.test.tsx

Tests for the tab strip were written before component implementation to guard critical screen reader accessibility attributes.

Every tab is marked with `accessibilityRole="tab"`. The active tab carries `accessibilityState={{ selected: true }}`, while inactive tabs receive `accessibilityState={{ selected: false }}`.

## LegislatorCard.test.tsx

Legislator card tests ensure card layout, tabular numeral styling, and conditional chart panels render predictably.

The tests cover composition from the shared `Card` building block, plus score tiles and charts toggle: party badge, `full_name`, and three score tile labels (Agreed / Disagreed / No vote). Each score value's `Text` sets `style.fontVariant` to include `"tabular-nums"` so digits align across columns. The charts toggle controls `LegislatorChartsPanel`, and toggling is omitted when `user_legislator_score` is null.

## LegislatorChartsPanel.test.tsx

The charts panel suite verifies SVG bar chart rendering and accessible row labelling across score distributions.

The SVG chart draws 4 `<Rect>` bars representing agreed, disagreed, abstained, and no-vote counts. Every row carries an `accessibilityLabel` formatted as `"{label} {value}"`. When all score counts equal zero, no rendered bar exceeds zero width.

## LocalePickerSheet.test.tsx

Locale picker tests verify raw hyphenated locale identifiers format into clean capitalized presentation labels.

The API sends `locale.name` as lowercase hyphen-delimited words such as `"baltimore-maryland-united_states"`, mirroring the web application shape. `LocalePickerSheet` processes values through `toFormattedLocaleName`, which capitalizes segments and joins them with comma separators. Test assertions target the formatted display string rather than the raw fixture identifier.

## MembershipCard.test.tsx / MembershipsListScreen.test.tsx

Membership components require ThemeProvider wrapping during test execution to support theme-aware card primitives.

The test suites evaluate components against finished implementations. Test renders are wrapped in `ThemeProvider` because the shared `Card` primitive utilized by `MembershipCard` invokes `useTheme()`.

## OrgCard.test.tsx / OrgDetailScreen.test.tsx

Organization card and detail test suites assert the track controls stay interactive and that no follower count renders.

`OrgCard.test.tsx` was written prior to rebuilding the component with the shared `Card` building block. Tracking an organization was temporarily removed from the application and subsequently restored; tests that previously verified the absence of the control now verify that it works. Both suites also assert that no follower count appears, because the organization follower count was removed. `OrgDetailScreen.test.tsx` similarly verifies the presence and action of the track controls.

## StampedBadge.test.tsx

Badge styling assertions verify pill geometry, accessible color contrast ratios, and flattened style definitions.

The badge geometry follows a pill container shape, with text colors selected to satisfy WCAG contrast ratio accessibility standards against background fills. Label `Text` sets `tabular-nums` for consistent digit widths.

A `flat()` helper normalizes style props into single plain objects because styles can arrive as arrays or numeric `StyleSheet` identifiers that `@testing-library/react-native` does not automatically flatten.

## UpdateBanner.test.tsx

The update banner renders above application navigators without interrupting active navigation hierarchies.

The banner component is structured to avoid blocking user navigation, requiring parent layouts to position it cleanly above root navigators.

## VoteButton.test.tsx

Haptic feedback spies initialize inside mock wrapper functions to prevent undefined references during module loading.

The spy `mockImpactAsync` is declared at file scope, and the `jest.mock` factory returns a wrapper invoking it during test execution when constants are initialized. Referencing the constant directly inside the factory would execute during module resolution before declaration, causing undefined runtime errors. Sibling suites like `useBills.test.ts` follow the identical pattern.

## BillCard.test.tsx

Bill card shadow constraints are verified through static source code inspection rather than runtime DOM assertions.

Prohibiting inline `shadowOffset` styling is enforced by scanning source text, leaving no separate runtime assertions required in the component test suite.

## useBootstrap.test.ts

Bootstrap tests attach listeners to AppState directly on the preset mock to prevent native module loading failures.

The test captures the `AppState` listener directly rather than mocking `react-native` with `requireActual`. Native modules in React Native 0.83 such as `DevMenu` and `SettingsManager` are absent under Jest and fail suite loading. The `jest-expo` preset provides stubbed modules, allowing tests to safely override `AppState.addEventListener` post-import.

## useSession.test.ts

Sign-out workflows retrieve stored session state prior to clearing credentials to retain device cleanup identifiers.

The `signOut` method invokes `sessionStore.get()` before clearing local storage, preserving the device identifier required for `DELETE /api/v1/devices/:id` unregistration requests.

## usePendingChanges.test.ts

Pending change mutation tests trace rejected change responses through client error wrappers to UI alert dialogs.

When the backend responds with HTTP 422 `{ error: { code: "already_finalized", message: "Change is already finalized." } }`, `apiClient` unpackages the payload into an `ApiRequestError`. The hook propagates the exception to `PendingChangesList`, which triggers `Alert.alert("Reject failed", err.message)`. Validating this end-to-end chain guards against regressions in server responses or client error handling.

## useInviteAccept.test.ts

Invite acceptance hook tests were constructed prior to implementation to establish the invitation lifecycle contract.

The suite establishes behavioral expectations for token acceptance, state transitions, and error handling before hook development began.

## AddressScreen.parity.test.tsx

Address parity tests verify address suggestions and post-submission navigation parity across client implementations.

The suite verifies suggestion provider consistency and ensures submission directs users to the expected destination. Because `AddressAutocomplete` imports `GooglePlacesSDK` as a default export, CommonJS module resolution requires `__esModule: true` in mocks so Jest resolves `.default` properly.

## AuthScreen.test.tsx / DeviceUnsupportedScreen.test.tsx

Authentication and unsupported device screens mount within ThemeProvider and verify linking and haptics via spies.

Both suites wrap renders in `ThemeProvider` because `Card` and `Pressable` invoke `useTheme()`. Snapshot testing is avoided due to circular references in theme objects that break snapshot formatters. `AuthScreen.test.tsx` spies on `Linking` using `jest.spyOn`, while `DeviceUnsupportedScreen.test.tsx` stubs `expo-haptics` interactions.

## BillDetailScreen.test.tsx

Bill detail tests traverse the rendered React tree depth-first to verify deterministic vertical ordering of sections.

Ordering verification collects test IDs through recursive depth-first tree traversal. Hand-traversal avoids `UNSAFE_getAllByProps` limitations with loose matchers while preventing call stack exhaustion on deeply nested `ThemeProvider` hierarchies.

The suite also verifies that `handleVoted` passes to `VotePanel` as `onVoted`. Testing with signed-out sessions ensures proper callback wiring and timer mounting without executing live votes.

## BillsListScreen.test.tsx

Category filtering tests verify union matching semantics across multi-category legislative fixtures.

Filtering checks test single-category selection against multi-category bills containing `\[Education, Police]`. The assertion confirms bills matching any selected category appear in filtered results rather than requiring an intersection of all selected categories.

## DeepLinkRouting.test.tsx

Deep link route configurations are validated directly without mounting native navigation containers in headless Jest.

Tests inspect linking configurations directly to avoid loading `react-native-screens` native libraries unmocked by `jest-expo`. Deprecation of the `PreviousBills` route is verified via an intentional `@ts-expect-error` directive against `BillsStackParamList`.

The bill detail cases resolve the link through `getStateFromPath`, one stack at a time. The full config registers `bills/:id` under both Home and Bills, and `getStateFromPath` throws on a config with a duplicate pattern, so it throws for every path, `legislators` included, while the duplicate stands. Each stack is resolved alone until one of the two registrations is removed.

## LegislatorDetailScreen.test.tsx / MembershipDetailScreen.test.tsx

Legislator and membership detail test specifications were authored prior to screen implementations.

Test cases predefined layout expectations, tab hierarchies, and interaction states before development of the respective screen components.

## LegislatorsListScreen.test.tsx

Legislator list tests cover modernized card layouts along with term toggling and legislative voting history views.

Initial test cases validated rebuilt list card rendering, while subsequent test blocks verify term selection toggles and the History tab interface.

## OrgsListScreen.test.tsx

Organization list regression assertions confirm retired filter bars and legacy follow labels remain removed from UI.

Assertions verify that `testID="org-filter-bar"` does not render and that legacy "Following" text is absent from modern screen layouts.

## PasskeyManagementScreen.test.tsx

Passkey management screens provide view-only credential listings without exposing deletion controls or dialogs.

The screen presents passkey credentials across loading, loaded, empty, and error states while deliberately omitting removal buttons and confirmation sheets.

