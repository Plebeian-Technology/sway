---
lat:
  mode: explanation
---
# User vote submission

User votes keep the same meaning across mobile and web controls. Their vocabulary follows [[naming-decisions#Two vocabularies, one per actor]].

## Mobile vote controls

The mobile vote panel accepts the bill and user_vote payloads directly, so screens do not reshape the server response before voting.

Its userVote and pendingUserVote values distinguish the recorded choice from the choice awaiting confirmation. UserVoteChoice names the button contract; the support wire field remains unchanged. Signed-out readers see the sign-in sheet only after attempting a vote.

The optional onVoted callback lets a screen refresh after success. Cache invalidation already belongs to the submission hook, so correctness does not depend on that callback. The className override lets the same panel sit tight under the title inside the Bill tab's hero card or fill a card of its own on the Votes tab.

Vote buttons preserve their accessibility role, label, state and hint contracts for screen-reader consumers and automated checks. Haptic feedback is fire-and-forget and precedes the action: a haptic call that rejects or throws is swallowed, so it can never block a vote. Press feedback is suppressed for disabled or selected buttons because those controls cannot cast another vote.

## Disabled mobile vote hints

A recorded vote is final, so both disabled buttons explain that it is already recorded, even when the phone is offline. Connectivity cannot make those buttons usable again.

An unrecorded vote receives an offline hint only when its caller explicitly supplies that reason. VotePanel knows connectivity; the reusable VoteButton does not infer it from disabled alone, which can also describe an in-flight operation.

The same reasons are also written out. VotePanel draws one caption under the buttons, so a sighted reader is told why the buttons are disabled. The hints cover a recorded vote and the offline case; the caption covers those two and a closed bill, which no hint mentions. The caption is a polite live region, chosen by priority: a recorded vote first, because a recorded vote is final whatever the connection; then a closed bill, whose voting is closed; then offline. It is hidden while the error line is showing, so two sentences never compete.

A bill is closed whenever the server reports it inactive ([[app/models/bill.rb#Bill#active]]), with or without a release date. [[app/controllers/user_votes_controller.rb#UserVotesController#create]] refuses every inactive bill, so a past Bill of the Month, or a scheduled bill in an inactive session, gets disabled buttons and the closed caption instead of controls that cannot succeed.

When the server still refuses, for example because the bill closed after the screen loaded, the error line shows the server's own message for the bill_inactive code. A retry cannot help there, so the generic retry text stays for other failures only.

## Mobile vote restoration

The server-provided vote wins over the device cache. The cache fills an absent server choice so a recorded vote remains visible offline or while refreshed data is still arriving.

A cancelled cache read cannot update an unmounted panel. This keeps an earlier asynchronous restoration from writing into a screen that has already been left.

## Submission hooks

Both clients call the action useCastUserVote. Separate platform implementations preserve their own transport and cache contracts while naming the same domain action.

The mobile hook refuses offline writes before the request. It sends bill_id and uppercase support at the top level of the request, matching the Rails parameter contract. A successful response records the local vote and invalidates the cached bill so a later load can obtain updated totals. Authentication errors remain the API client's responsibility and propagate to callers, as does every other server refusal with its error code and message intact, so VotePanel can tell a closed bill from a failure a retry can fix.

The web hook centralizes confirmation, optimistic display, offline handling and notifications for every themed panel. Inertia useForm updates its request-data reference after rendering; its transform callback supplies the selected support at request construction time so a same-tick post cannot submit stale state.

On an error the web hook restores the server-provided vote, including an absent choice, and clears the pending state so a failed optimistic choice does not remain recorded on screen. The useForm test mock keeps data in React state to make that rollback observable.

## VoteComparisonPlaceholder component

The `VoteComparisonPlaceholder` component renders when a vote comparison is hidden due to low user engagement, specifically when fewer than ten users have voted on a bill. It informs readers of the threshold and provides a path to invite others.

It exists in two states based on `votersNeeded`:
- When `votersNeeded` is present, it displays the specific count of users required for comparisons, the line "Invite others by sharing Sway", and a button to either copy an invite link (if signed in) or link to the sign-up page (if signed out). A signed-in user whose `invite_url` is null sees the count alone, with neither the line nor the button.
- When `votersNeeded` is absent, it renders a simple 'Not enough votes yet' line.

The component reuses strings from `[[app/frontend/sway_constants/parityCopy.ts#bill]]` to ensure parity between web and mobile applications. It uses `navigator.clipboard.writeText` and a `react-hot-toast` toast to handle invite link copying for signed-in users.

## Themed web vote controls

The default, ballot and corner-store controls share submission behavior so theme choice cannot change what casting a vote means.

For and Against colors come from semantic vote tokens, rather than one fixed palette. The ballot control uses a pencil-like oval and recorded stamp to mirror a ballot; the corner-store control uses poster blocks. These presentations all consume the same hook state and handlers.

The default control arranges its two choices by the width it is given, with an 8rem minimum per column bounded by the available width: a 360px phone already seats them side by side, the way a ballot lists its choices, and only the narrowest 320px viewport stacks them. The labels step down to the lede size below `sm:` so "Against" fits a phone-width column without wrapping. Descriptions wrap inside each button instead of inheriting the shared button primitive's no-wrap text style. Browser tests measure the text bounds at phone and desktop widths; vote state and handlers are unchanged.

### Where the default control sits

The default layout renders the ballot inside the hero card, directly under the bill's title, because casting a vote is the one thing the page asks of a reader and the title is the one thing every reader looks at first.

Before this the control was a card of its own: above 1280px in a 20rem column beside the reading column, and on a phone below a header that carried the bill's full legal long title and a sponsor box. A phone reader scrolled past the whole legal clause before meeting the buttons, and on a desktop the card sat at the edge of the page at the height of the score panel, the size of a filter. The mobile app's featured screen had already put the headline and the vote controls in one card ([[user-vote-submission#Mobile bill screen refresh]]); the web hero now does the same.

Two things left the hero to make room. The legal long title moved to the end of the reading column, where the ballot and banner layouts already keep it, as an appendix rather than an opening. The sponsor box collapsed to a byline under the title: one line naming the sponsor, one muted line carrying the vote date and the sponsor-counts-as-For note.

The control is a plain section rather than a card, so its frame belongs to whichever layout seats it: the hero closes with it under a rule, and the banner layout's returns box holds it under a rule of its own. A sticky rail beside the reading column was the rejected alternative; it keeps the control in view but keeps it at the edge, which is the placement the change exists to undo.

`spec/system/bill_page_ballot_spec.rb` opens a bill with a real five-line phone title in a real browser at phone and desktop widths and reads the boxes of the title, the two buttons and the score panel: the ballot lies below the title and above the score panel, both buttons lie inside the first screen, and the choices sit side by side at 390px and stack at 320px. jsdom has no layout engine, so the unit test in `billLayoutRender.test.tsx` checks only that the ballot is nested in the hero, ordered after the title and before the score panel, and that the legal clause is no longer in the hero.

## Mobile bill screen refresh

The mobile detail and featured-bill screens refresh through focus-bound score subscriptions, reconnection updates and a 15-second poll. Inactive screens stop polling to avoid work for content the reader cannot see.

After a vote, a 1500ms delayed refresh allows score work to finish; cleanup cancels that timer if the screen leaves. The featured screen obtains connectivity from useCastUserVote. Its first paint comes from bootstrap and the rest of the bill from the bill detail response, so the delayed refresh reloads both; its stable refresh callbacks avoid accumulating focus timers across renders ([[bill-page-polling-props-rationale#Mobile: useFocusedSync on BillDetailScreen and BillOfTheMonthScreen]]).

Both screens split the bill into Bill, Votes and Summaries tabs, one mounted at a time. The Bill tab groups the headline and vote controls in one card so voting remains attached to the legislation being described, then carries the summary and the full title. The Votes tab repeats the vote controls above scores, by-district tallies and hearing links; the Summaries tab carries related news, organization positions and, for signed-in readers, constituent-letter counts. The tabs are keyed by bill id, so a refetch of the same bill keeps the reader's tab while a different bill opens on the Bill tab. Selecting a locale on the featured screen persists the choice and updates the API client's sway_locale_id query parameter before refetching bootstrap; bearer-token mobile requests do not rely on a browser locale cookie.

## Mobile screen coverage

The detail-screen ordering check presses each tab and walks the mounted test instance tree, so it measures visual section order within a tab rather than the order a test happens to query elements.

A walk of the raw fiber tree can return the previous tab's sections after a press, which is why the check reads the instance tree.

Screen integration tests render the voting section with hook mocks; submission and cache behavior are verified in hook tests. The detail and featured screen tests also cast a vote from the Votes tab and advance fake timers, which shows the panel's post-vote callback reaches the screen's delayed refresh.

The featured-screen tests feed bootstrap only the keys `Bill#to_builder` emits and supply the sponsor, scores, positions and news through a mocked `useBill`. A fixture richer than the server's payload would hide that those fields are absent from bootstrap.

## Browser examples prove the web vote reached the server

The system vote waits for the success toast, not the optimistic recorded marker, because the marker appears before the request. It also checks the saved vote row and support value so a stale form submission cannot pass on presentation alone.

A separate example drives an ordinary bill page because the Bill of the Month example cannot establish the same panel works on that route.

## The stale browser panel returns to the server's final vote

The system example opens a live panel, records an Against vote elsewhere, then submits the stale For choice. It waits for the server's refusal and verifies that only the recorded Against choice remains.
