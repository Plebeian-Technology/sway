---
mode: explanation
summary: Design rationale for the mobile bill-screen components — BillCard, BillContent, BillHeader, BillScoreBar, BillSummarySection, BillsSortStrip, CategoryChipStrip, HearingTestimonySection, VoteButton, and VotePanel.
status: agent-extracted
related: []
---

# Mobile bill surface components

## BillCard

One bill summarised on a card, built from the shared Card pieces.

What it looks like:
- The Card itself supplies the shadow, border, and rounded corners; nothing sets a
  shadow here.
- A row of pills: the bill's external id (yellow), its category (muted), and, only
  when the user has voted, their own vote (blue).
- The bill title, 2xl semibold.
- A summary excerpt: the first 180 characters, with the NEWLINE and ENDING markers
  taken out, or stand-in text when there is no summary.
- Two score boxes side by side, For and Against, in fixed-width digits so the numbers
  line up.
- An "Open bill" button in the card footer.
- The card tells screen readers "Open bill {bill.title}".

## BillContent

The bill's text plus Sway's own summary. It follows the website's
BillContent.tsx but shows less: the Sway summary block, a section-by-section preview
when there is one, and the bill text. The website's charts (BillChartsPanel and
BillAffinityPanel) are deliberately left out here, to keep the screen calm.

Accessibility: each block is marked accessibilityRole="text" with a clear label, so
VoiceOver moves through them as separate sections instead of one long blob.

## BillHeader

The bill title (20pt semibold), a muted 14pt line naming the sponsor and
the locale, and a StampedBadge for the bill's status. It follows the website's
BillHeader.tsx, rebuilt with React Native components and kept plainer: none of the
web version's heavy decoration.

Accessibility: the whole header is marked as a "header" landmark, so VoiceOver and
TalkBack read it out as the screen's heading. The sponsor line is its own `text`
element with a clear label.

### `hero` prop

Headline size. Grows the title from the usual 20pt to 30pt, so the Bill of the
Week reads as the main event on its screen. Both sizes come from the sway.css
type scale; leaving this false keeps the normal size.

### `BillOfTheWeekScreen`'s headline card

What the bill is, plus the vote buttons, are grouped into one raised card
so this headline screen has an obvious centerpiece. The rest of the
sections, each already in its own card, fade in one after another
beneath it.

## BillScoreBar

How the whole locale voted, as one horizontal bar split between for
and against.

How it looks:
- the surface-3 background, the shade used for a card sitting on another card;
  the same surface the website's "How others voted" block uses.
- vote counts in fixed-width digits, so a count going from 9 to 10 does not shove
  the layout sideways.
- the vote-for and vote-against colours for the two parts of the bar, the same
  colours the website uses.

Accessibility: a screen reader hears one sentence with the percentages — splitting
the bar in two is a visual device and means nothing out loud.

### Animated width

The bar used to jump straight to its new width every time live scores arrived
over the WebSocket or a poll. Now the width slides, so a changing tally looks
like movement instead of a snap. It starts at the current percentage, so the
first paint matches the data, and later changes glide to the new value.

## BillSummarySection

Shows a short preview of the bill summary, and opens out to the
full text when tapped. Opening and closing are animated with
LayoutAnimation.configureNext, so react-native-reanimated is not needed here.
[platform] the website prints the whole summary at once; on a phone it starts folded.

### `summaryAiUnreviewed` prop

True when the summary is a machine's words that no person revised. A
notice then goes under it. The sentence comes from the
shared copy file, so it reads the same here as on the website.

## BillsSortStrip

A sideways-scrolling row of sort choices for the bills list.
It looks like CategoryChipStrip but behaves like a set of radio buttons: exactly one
choice is always on. The choices and their labels come from
PARITY_COPY.bills.sortOptions, the same list the website's BILLS_SORT_OPTIONS
re-exports, so the two cannot drift apart.

## CategoryChipStrip

### `titleize`

Capitalise each word of a category name for display, the same way the website's
sway_utils.titleize does: lowercase everything, then upper-case the first letter of
each space-separated word. It is copied here rather than imported, because
sway_utils may reach for browser-only APIs. This is for display only — filtering
still compares the raw category values.

## Shared ScrollView fix: `flexGrow: 0`

Both `BillsSortStrip` and `CategoryChipStrip` set `style={{ flexGrow: 0 }}` on their
horizontal `ScrollView`. Without it the strip stretches and swallows all the
leftover height in the BillsList column.

## HearingTestimonySection

The "Take the next step" card, whose links open in a
browser inside the app.
Security: before opening a link we check that it is https and that its host is on our
approved list.
[platform] the website opens a new browser tab; the app opens the built-in browser
view (SFSafariViewController on iOS, Custom Tabs on Android).

### `ALLOWED_HOSTS`

The only sites bill.link is allowed to point at. The value comes from our own Rails
database, so it should already be safe; checking again here means a wrong entry can
never bounce a user off to somewhere else.

The list holds the known government legislature domains plus the domains for
particular locales, matching the hosts in VOTING_WEBSITES_BY_LOCALE in locales.ts. It
is written out here rather than imported, because locales.ts uses a TypeScript enum
that mobile's Jest setup cannot compile (@babel/runtime is not available to the web
constants).

### `LOCALE_LINK_LABELS`

What to call the outside site in the link label, looked up by locale name.
A plain-object copy of VOTING_WEBSITES_BY_LOCALE from
app/frontend/sway_constants/locales.ts, copied for the same reason as the host list
above: importing locales.ts would pull in a TypeScript enum that mobile's Jest cannot
compile.

### `onNavigateToLegislators` / `onNavigateToBills` props

The screen supplies these; they are optional so the card can render on its own.

### `handleOpenBill` defense in depth

The link comes from our own server, but refuse it anyway rather than
send a user somewhere unexpected. Log only in development, so crash
reports from real users never carry the blocked URL.

## VoteButton

One of the two buttons a user taps to vote on a bill.

- At least 44×44pt, the smallest comfortable tap area.
- Chosen "For": green background, text in the successForeground color token.
- Chosen "Against": red background, white text.
- Not voted yet: the muted secondary background with a 1.5pt border.
- Pressing it buzzes the phone once, lightly
  (Haptics.impactAsync(ImpactFeedbackStyle.Light)). This is the only place in
  the whole app that uses haptics.
- The label reads "For" or "Against", set in 14pt SemiBold.

Screen-reader wiring. An automated check greps for these props, so they must
stay:
- accessibilityRole="button"
- accessibilityLabel=`Vote for ${billTitle}` / `Vote against ${billTitle}`
- accessibilityState={{ selected: active, disabled }}
- accessibilityHint — the exact wording is fixed by the design spec.

### Press-feedback gating

The button visibly reacts while you hold it down, but only while it can still be
used. After a vote is cast it is disabled or already selected, and the press
feedback does nothing.

## VotePanel

The voting section of a bill's detail screen. It works the same
way as voting on the Bill of the Week screen: two buttons, For and Against.
Anyone may read a bill without an account, so the sign-in sheet
(AuthPromptSheet) only appears once a signed-out person tries to vote.
Casting a vote needs a live connection, which useVote enforces.

The list of props is kept short on purpose, so BillDetailScreen can hand over
the `bill` and `user_vote` values exactly as Rails sent them, with no
reshaping in between.

### `onVoted` prop

Runs once a vote goes through, so the parent can reload its data and drop
stale copies. Optional: useVote.submit already clears this bill's cached
copy by itself.

### `className` prop

Overrides the space around the panel. The default "mt-6 mb-2" suits the
bill detail screen, where the panel stands on its own. The Bill of the
Week card passes something tighter so the panel tucks under the bill's
title block inside the same card.

### Stance restore precedence

Bring back the user's choice when they leave this screen and return. What the
server sent wins. If the server sent nothing, fall back to voteCache, the local
copy useVote saves so the app still knows your vote while offline. The Bill of
the Week startup payload already carries user_vote, so this mainly covers being
offline or arriving before the cache has loaded.
