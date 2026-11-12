---
lat:
  mode: explanation
---

# Mobile bill surface components

Why the mobile bill screens are built the way they are: one three-tab composer shared by the detail and featured-bill screens, the panes it assembles, and the voting controls inside them.

## BillAsIntroduced

The block that prints a bill's full stored title under an "As introduced" label, on the Bill tab of both bill screens.

It renders whenever the stored title carries more than the header's headline, as decided by [[mobile/src/utils/billTitle.ts#hasMoreThanHeadline]]. That covers a title with the legal enacting clause, "FOR the purpose of ...", and a title with a deck after a dash; the header drops both, so this block is the only place a reader sees them. A title that is a single phrase is already whole in the header, so a second copy would only add noise. The website's component differs: its header prints the deck beside the headline, so it hides itself only when the clause is absent ([[bill-as-introduced-title-split#Why BillAsIntroduced exists]]). The label text is `PARITY_COPY.bill.asIntroduced`.

This is the one place in the app that shows the full stored title. Headers, cards and sheets show only the headline ([[bill-title-display#Where only the subject is shown]]), because a clause of several hundred characters crowds out status, counts and actions on a phone. Keeping the full wording in one quiet block on the Bill tab leaves it readable for a reader who wants it without costing any other surface its room.

A title longer than [[mobile/src/components/BillAsIntroduced.tsx#FOLD_ABOVE_CHARS]] characters folds to [[mobile/src/components/BillAsIntroduced.tsx#COLLAPSED_LINES]] lines behind a Show more toggle, so the block does not push the end of the Bill tab far down; a shorter title is never clamped and draws no toggle. The title text is selectable.

Accessibility: the label is marked as a header and the title as text, so a screen reader announces the block as its own section.

## BillCard

One bill summarised on a card, built from the shared Card pieces.

What it looks like:

- The Card itself supplies the shadow, border, rounded corners and a 5px coloured left edge: the reader's vote colour once they have voted, the primary blue otherwise.
- A row of pills: the bill's external id (solid blue), its category (pale blue tint), and, only when the user has voted, their own vote in the vote colour.
- The bill headline, lg semibold, clipped to three lines.
- A summary excerpt: the first 160 characters, with the NEWLINE and ENDING markers taken out, or stand-in text when there is no summary, clipped to two lines.
- One row holding the For and Against scores in fixed-width digits, followed by the "Open bill" button.
- The card tells screen readers "Open bill {bill.title}".

The layout is shortened on purpose: see [[mobile-chrome-and-scroll-layout#Cards carry a coloured edge]].

## BillHeader

The bill number and chamber, the headline (20pt semibold), category chips, a muted 14pt line naming the sponsor and the locale, and a StampedBadge for the status; the sentence about when legislators voted is optional.

It follows the website's BillHeader.tsx, rebuilt with React Native components and kept plainer: none of the web version's heavy decoration. The categories, the vote sentence and the "may no longer be in office" line carry the same facts as the web header.

Accessibility: the headline is the header element; the container carries no role. The bill-number line is a `text` element whose label adds the chamber, and the sponsor line is its own element with a clear label.

### Sponsor link

When the screen passes `onSponsorPress` and the sponsor has a name, the sponsor's name is drawn as a link with a 44pt minimum height that opens the sponsor's legislator page.

Both screens pass the handler only when the bill has a `legislator_id`, and [[mobile/src/components/BillScreenTabs.tsx#BillScreenTabs]] drops it again when that id is missing, so a bill without a sponsor shows no dead link. Without the handler the line is plain text.

### Showing the vote sentence

`showVoteStatus` decides whether the header draws [[mobile-bill-surface-components-design#BillVoteStatus]] under the badge. It defaults to true, so a header mounted on its own still shows the sentence.

The only caller, [[mobile-bill-surface-components-design#BillScreenTabs]], passes false and places the same sentence under the vote buttons instead.

### Status colour is derived on the phone

The server never sends `status_color`. `Bill::Status` is passed, failed, committee or vetoed, and nothing in `app/` or `lib/` emits a colour.

The badge draws only when it has a colour, so [[mobile/src/utils/billStatus.ts#billStatusColor]] derives one from the status and the colour scheme: the scheme's success colour for passed, destructive for failed and vetoed, warning for committee, and muted foreground for any other status. [[mobile/src/utils/billStatus.ts#billStatusLabel]] capitalises the status for the label. The fill follows light and dark mode, and the badge picks white or dark ink for whichever fill it receives ([[mobile-shared-primitives-design#StampedBadge]]). A `status_color` on the bill itself still wins over the derived one, so a server that starts sending a colour needs no change on the phone.

### hero prop

Headline size. Grows the title from the usual 20pt to 30pt, so the Bill of the Month reads as the main event on its screen.

Both sizes come from the sway.css type scale; leaving this false keeps the normal size. Only the featured-bill screen passes it, through [[mobile-bill-surface-components-design#BillScreenTabs]].

## BillScoreBar

How the whole locale voted, as one horizontal bar split between for and against, under the "How others voted" title.

The Votes tab supplies the card around it; the component draws its own title, an empty track behind the two segments, and the counts below.

- Counts and percentages sit in fixed-width digits, so a count going from 9 to 10 does not shove the layout sideways, and counts carry thousands separators from [[mobile/src/utils/districtVotes.ts#formatVoteCount]].
- The segments use the vote-for and vote-against colours, the same colours the website uses.
- The empty track is the muted colour in light mode and the border colour in dark mode, where the muted colour equals the card colour and the track would vanish. [[mobile-bill-surface-components-design#DistrictVotesPanel]] draws its tracks the same way.
- With no votes at all the track stays empty and a muted "No votes recorded yet." sentence replaces the two counts.
- Until the detail response has arrived the Votes tab shows a skeleton instead of this bar ([[mobile-bill-surface-components-design#BillScreenTabs#Why the Votes and Summaries tabs wait for the detail response]]).

Accessibility: a screen reader hears one sentence with the percentages and the total, or the no-votes sentence — splitting the bar in two is a visual device and means nothing out loud.

### Animated width

The two segments slide to a new width over half a second with an ease-out curve whenever live scores arrive over the WebSocket or a poll, so a changing tally looks like movement instead of a snap.

The shared values start at the current percentage, so the first paint matches the data and only later changes animate.

## BillScreenTabs

The one place that composes the Bill, Votes and Summaries tabs, so the bill detail screen and the featured-bill screen draw the same panes from the same props.

[[mobile/src/components/BillScreenTabs.tsx#BillScreenTabs]] wraps [[mobile-bill-surface-components-design#BillSectionTabs]], keyed by bill id. It takes the bill, the sponsor, the user vote, the locale score with its per-district tallies, the organizations, the reader's own districts, the locale slug and portal URLs, the public testimony counts and a signed-in flag. It also takes two flags describing the detail response (loaded, error) with a retry callback, the vote, navigation and sponsor callbacks, a `hero` flag and two test ids. The screens differ in where that data comes from and what sits above the tabs; the pane markup exists once. What each tab holds is listed in [[mobile-bill-detail-and-bill-of-the-month-screens]].

Within a pane the sections fade in one after another. Only the active tab's pane is mounted, so only one VotePanel exists at a time.

### Why the Bill tab holds the hero card, the summary and the full title

The Bill tab is the one every reader lands on, so it carries what the bill itself says.

It opens with the header, the vote buttons and the vote sentence in one raised card, so voting stays attached to the legislation being described and the featured screen has an obvious centerpiece. Sway's summary follows with its source notice and, under the card, a control for reporting an inaccurate summary ([[bill-summary-reporting#Reader reporting of inaccurate summaries#Reporting from the mobile Bill tab]]), then, when the title carries more than its headline, the full stored title under [[mobile-bill-surface-components-design#BillAsIntroduced]].

Sway's own summary sits on the Bill tab. The Summaries tab carries what others say about the bill: related news, organization positions and constituent letters.

### Why the Votes tab repeats the vote buttons

The Votes tab opens with its own VotePanel in a card of its own, so a reader who has just looked at the tallies can vote without going back to the Bill tab.

The two panels are deliberate and never on screen together, because only the active tab is mounted. Both read the same `user_vote`, and a vote reloads the detail response ([[user-vote-submission#Mobile bill screen refresh]]).

### Why the Votes and Summaries tabs wait for the detail response

The Votes and Summaries tabs show a skeleton while the detail response is loading and a retry row if it fails, instead of tallies and empty-state sentences computed from nothing.

The sponsor, the locale score, the organizations and the district tallies all arrive in that response. Reading them before it lands would draw a bill nobody has voted on and organizations that have no position, both false. The skeleton keys off the screen's `detailLoaded` flag rather than off the score being null, for two reasons: the server sends `bill_score: null` for a bill with no score yet, which is a real answer, and the detail hook raises its loading flag on every poll, so keying off loading would flash the skeleton every fifteen seconds. A failure with no data draws the shared "could not load" sentence and a retry button that reloads the detail. The retry row ignores the loading flag too: a failed first load keeps its error through each poll's reload, so the row stays put instead of swapping for a skeleton every fifteen seconds while the server is down.

The Bill tab does not wait: its header, summary and vote buttons need only the bill's own fields, which the featured screen already has from bootstrap.

### Why the Summaries tab is never blank

`OrgPositionsSection` always draws its two cards, with a muted line in an empty one, so the tab has content even for a bill nobody has taken a position on.

`RelatedNewsArticles` and the constituent-letter card draw nothing when the bill has no related articles or no letters ([[news-mobile-links#Zero-node suppression and screen lifecycle]], [[mobile-bill-surface-components-design#PublicTestimonySection]]), and the tab does not reserve a gap for them.

### Why the featured screen fetches the bill detail too

The panes need a sponsor, a locale score with district tallies, the reader's districts, organizations, related news, news commentary and constituent-letter counts, and the bootstrap response's featured bill carries none of them.

That bill holds only its own fields, cached per locale and shared between readers, with the reader's vote merged in afterwards ([[bootstrap-caching-and-rate-limiting#Why locale and featured bill are cached per locale]]). The featured screen therefore paints from bootstrap first, since the header, summary and vote buttons need nothing more, and fetches the same bill detail response the detail screen uses, layering it over the bootstrap bill when it arrives. Sharing the response is what lets the composer receive one data shape from both screens, and the featured screen needs no endpoint of its own. Constituent-letter counts depend on who is reading, so they are read from the detail response only and never from bootstrap.

The detail hook needs a bill id, so it can run only after the screen's loading and no-featured-bill early returns, and it has to start clean when the featured bill changes, as it does on a locale switch. A shell that owns bootstrap, with a body keyed by the featured bill's id that owns the detail hook, provides both: the body mounts once there is a bill and remounts, with its hook reset, for another. The lookup facts are in [[mobile-bill-detail-and-bill-of-the-month-screens#BillOfTheMonthScreen's data source quirks]].

## BillSectionTabs

Splits a long bill screen into Bill, Votes and Summaries tabs, so an iPhone SE reader moves between three short pages instead of one long scroll.

[[mobile-bill-surface-components-design#BillScreenTabs]] is its only caller, so the two bill screens split the same way. It reuses [[mobile-shared-primitives-design#BroadsideTabStrip]] and renders only the active tab's content. It opens on Bill and keeps the choice in local state; BillScreenTabs gives it the bill id as its React key, so a different bill opens on Bill again while a refetch of the same bill keeps the tab.

## BillSummarySection

Shows a short preview of the bill summary, opens out to the full text when tapped, and carries the notices that belong under it.

Opening and closing are animated with `LayoutAnimation.configureNext`, so `react-native-reanimated` is not needed here. On Android, React Native only runs `LayoutAnimation` transitions after `UIManager.setLayoutAnimationEnabledExperimental` has been enabled at module load. Legacy `NEWLINE` and `ENDING` markers left by older bill imports are stripped from the summary string in [[mobile/src/components/BillSummarySection.tsx#BillSummarySection]] before it is parsed as [[mobile-markdown-rendering|markdown]]. \[platform] the website prints the whole summary at once; on a phone it starts folded.

An empty summary, or the server's literal placeholder "Summary pending" ([[ai-unreviewed-notice-component-design#AiUnreviewedNotice component design#The pending-summary sentinel is not published AI text]]), draws a muted pending sentence (`PARITY_COPY.bill.summaryPending`) in place of the markdown, with no fold toggle and no unreviewed-AI notice, because the placeholder is not published AI text.

### summaryAiUnreviewed prop

True when the summary is a machine's words that no person revised. A notice then goes under it. The sentence comes from the shared copy file, so it reads the same here as on the website.

### Source notice

The bill screens ask for a ruled block under the summary that points to the official text.

When [[mobile/src/components/HearingTestimonySection.tsx#canOpenSourceLink]] passes, the block holds a "View official bill text" link with a 44pt minimum height that opens the in-app browser; otherwise it holds the sentence "Official source link is not available". The unreviewed-AI notice, when shown, sits above the source line inside the same block.

The notice puts the official text one tap from the summary it condenses, as the website's summary notice does, and the same unavailable sentence appears on the web and on the Votes tab ([[unlinked-bill-presentation#Cross-platform parity in unlinked presentation]]).

## BillVoteStatus

The sentence saying whether and when legislators voted on the bill, with a second line when the legislators who voted may no longer be in office.

On the bill screens it sits under the vote buttons in the hero card, not in the header above them. The sentence runs to several lines on a small phone, and above the buttons it would push them off the first screen of an iPhone SE; below them the buttons stay in view and the sentence is still next to the vote it explains.

[[mobile/src/utils/billVoteStatus.ts#billVoteStatus]] chooses the sentence from the bill's `vote_date_time_utc`, `house_vote_date_time_utc` and `senate_vote_date_time_utc`. The wording lives in the shared PARITY_COPY file (`bill.voteStatus`) and only the phone reads it from there; the web header holds the same sentences as inline strings.

- No vote date: legislators have not yet voted, and Sway records the sponsor and any co-sponsors as voting For until they do.
- Both chamber dates: one sentence naming each chamber and its date.
- One chamber date: a sentence naming that chamber and its date.
- A vote date with no chamber date: a sentence naming only the date.
- An inactive bill that has a vote date adds a second line, in the destructive text colour, saying the legislators who voted may no longer be in office.

Dates read like "March 3, 2026" and are formatted in UTC, so every reader sees the same calendar day whatever their timezone.

## BillsSortStrip

A sideways-scrolling row of sort choices for the bills list.

It looks like CategoryChipStrip but behaves like a set of radio buttons: exactly one choice is always on. The choices and their labels come from PARITY_COPY.bills.sortOptions, the same list the website's BILLS_SORT_OPTIONS re-exports, so the two cannot drift apart.

## BrowseTestimonySheet

A full-screen sheet that lists a bill's constituent letters ten at a time, filtered by stance, opened from [[mobile-bill-surface-components-design#PublicTestimonySection]].

The letters are the ones the website's modal shows ([[testimony-letters#Browsing constituent testimony in the modal]]); the phone differs in how it holds them.

- **Mounts only while visible.** A hidden sheet renders nothing, so each open starts on the tab the reader pressed with the first ten letters and a fresh scroll position.
- **Pages by ten.** A Show more button reveals ten more; changing tab resets to ten and scrolls to the top. The website pages the same size.
- **Its own tab strip.** All, Support, Oppose and Neutral each show their label above their count in a local strip, because the shared segmented control truncates labels. Each tab is at least 44pt tall and reports whether it is selected.
- **Sheet behaviour.** On iOS it is a page sheet that can be swiped away; a Close button and the Android back action also dismiss it.
- **Plain selectable text.** A letter is rendered as plain text the reader can select, not as markdown, so the words appear exactly as the constituent wrote them. Each card carries the letter's label and a stance badge that a screen reader announces as "Position: {stance}".
- **Never logs letter text.** The sheet, the section and the hook write no letter text to any console channel, and `console.error` reaches the error tracker in production ([[console-channels#Why warn and error are left alone]]); the letters are private writing.

Loading shows three skeleton cards and a polite live-region sentence; a failed load with nothing in hand shows the load-error sentence with a retry button; a stance with no letters shows the empty sentence.

## CategoryChipStrip

Horizontal scrollable chip component providing bill category filtering and active selection state feedback.

### titleize

Capitalise each word of a category name for display, the same way the website's sway_utils.titleize does: lowercase everything, then upper-case the first letter of each space-separated word.

It is copied here rather than imported, because sway_utils may reach for browser-only APIs. This is for display only — filtering still compares the raw category values.

## Shared ScrollView fix: flexGrow: 0

Both `BillsSortStrip` and `CategoryChipStrip` set `style={{ flexGrow: 0 }}` on their horizontal `ScrollView`. Without it the strip stretches and swallows all the leftover height in the BillsList column.

## DistrictVotesPanel

How each district voted on a bill, as For and Against bars and a net chart, with the reader's own district shown first in its own block and highlighted in both charts.

The data is the per-district tally the bill response already carries in `bill_score.districts`, shaped by [[mobile/src/utils/districtVotes.ts#selectDistrictVotes]]; no separate request exists and the server has no district-statistics endpoint. The reader's districts come from the response's `districts` key, which the detail request does not name in its omission header. The website draws the same tallies in [[bill-vote-charts-design#DistrictVotesChart.tsx]].

- **The at-large district is skipped.** District number 0 is dropped from the rows, as the website's charts drop it, because an at-large placeholder distorts a comparison between districts.
- **The reader's districts are matched by number and region code.** The server reads a district's number from the digits of its name and its region code from the letters, so two districts can share a number (`1A` and `1B`) and only the region code tells them apart. A match therefore needs number and region code to agree when both sides carry both, and falls back to the district name when either side lacks one. A reader district with no tally still appears in the "Your district" block, with a no-votes sentence, so the reader always sees their own district.
- **Only a bill from the active locale gets a reader district.** The response's `districts` list belongs to the locale of the request, while the tallies belong to the bill's own locale, and a number and region code can repeat across locales, since a district name such as "MD1" can exist in more than one. [[mobile/src/screens/BillDetailScreen.tsx#BillDetailScreen]] therefore passes the list only when the bill's `sway_locale_id` equals the active locale's id, and passes none when either id is missing; the tallies still show, with nothing highlighted. The featured bill always belongs to the active locale, so the featured screen passes the list as it arrives.
- **The wording is neutral.** A reader who has voted sees a sentence that their vote matches or differs from their district's majority, a tie sentence, or a no-votes sentence. It reports a fact and does not rate it, and a reader who has not voted sees no sentence at all.
- **Eight rows, with the reader's pinned.** Past [[mobile/src/components/DistrictVotesPanel.tsx#COLLAPSED_ROWS]] districts the list folds behind a "Show all N districts" toggle that always keeps the reader's rows visible, so a locale with many districts does not push the next card far down the Votes tab. The spoken summaries say how many districts are hidden.
- **The net chart is hidden when every district ties.** A net chart of zeros shows nothing, so it appears only when some district's For and Against differ.
- **The card appears only when some district has votes,** and only once the detail response has loaded, so a pending or empty tally never shows as an empty panel.
- **Rows reflow at large text sizes.** The district label and the count have minimum widths rather than fixed ones, so "District 12" is never truncated and a count grows with the text, and both legends and the reader block's For and Against line wrap onto a second line instead of running off a narrow phone.
- **Representatives are named on the by-district rows.** A row shows its district's `legislator_names` as a muted line under its bars and says nothing when the list is empty. The net chart leaves them out. The source and the layout reasons are in [[district-chart-tooltip#The mobile bill JSON carries the names, the web page does not]].
- **The labels say For and Against.** A vote on the phone is For or Against ([[docs/terminology.md]]); the website's charts say Support and Oppose.

Accessibility: each chart is one image element with a spoken summary of every visible row, flagging the reader's district, and the net chart speaks "plus" and "minus" instead of signs. The by-district summary adds each row's representatives in parentheses.

## HearingTestimonySection

The "Take the next step" card, whose links open in a browser inside the app.

Security: before opening a link we check that it points at a specific bill, is https, and has a host on the approved list for the bill's locale; [[mobile/src/components/HearingTestimonySection.tsx#canOpenSourceLink]] runs both the validity check and the host check and is shared with the summary's source notice. A link that fails is not drawn as a button: the card shows the "official source not available" sentence in its place, so the reader is told rather than handed a button that does nothing. \[platform] the website opens a new browser tab; the app opens the built-in browser view (SFSafariViewController on iOS, Custom Tabs on Android).

The source button's label wraps and centers so a long locale label such as "View on Baltimore County Website" stays inside the card at large type sizes.

### ALLOWED_HOSTS

The default set of sites bill.link is allowed to point at. The value comes from our own Rails database, so it should already be safe; checking again here means a wrong entry can never bounce a user off to somewhere else.

The set is [[mobile/src/constants/officialSourceHosts.ts#DEFAULT_ALLOWED_HOSTS]]: the known government legislature domains. [[mobile/src/constants/officialSourceHosts.ts#getOfficialSourceHosts]] adds the hosts registered for the bill's own locale, so a link passes when its host is in the defaults or in its locale's list.

### LOCALE_LINK_LABELS

What to call the outside site in the link label, looked up by locale name.

A plain-object copy of VOTING_WEBSITES_BY_LOCALE from app/frontend/sway_constants/locales.ts, copied rather than imported, because importing locales.ts would pull in a TypeScript enum that mobile's Jest cannot compile.

### onNavigateToLegislators / onNavigateToBills props

The screen supplies these; they are optional so the card can render on its own.

### handleOpenBill defense in depth

The link comes from our own server, but refuse it anyway rather than send a user somewhere unexpected.

The handler repeats the `canOpenSourceLink` check that decides whether the button is drawn, and returns without logging when it fails. No build logs the blocked URL, so crash reports from real users never carry it.

## PublicTestimonySection

The Summaries tab's card of constituent-letter counts by stance, shown only to signed-in readers, whose pills and Browse button open [[mobile-bill-surface-components-design#BrowseTestimonySheet]].

This is a different thing from the published news commentary beside the organization positions ([[news-mobile-testimony#Placement of published commentary inside support and oppose cards]]): these are letters constituents sent to the hearing, counted and browsed, never summarised.

- **Counts come from the detail response.** The `public_testimony_counts` key carries a total and a count each for support, oppose and neutral, and is null for a signed-out reader. The featured screen reads it from the merged detail response only, never from bootstrap.
- **Zero nodes unless there is something to show.** The section renders nothing when the reader is signed out, the counts are missing, or the total is 0, and [[mobile/src/components/BillScreenTabs.tsx#BillScreenTabs]] does not mount it in those cases either. The server gate is in [[testimony-letters#Presenting public testimony on bill pages#Signed-out readers receive no public testimony]]; no sign-in prompt replaces the card.
- **Pills choose the tab.** Support, Oppose and Neutral each open the sheet on that stance, at least 44pt tall; the Browse button opens it on All. The stance words are the display words for a stance, not the For and Against of a vote ([[docs/terminology.md]]).
- **Letters load when asked for.** The card holds only counts. [[mobile/src/hooks/usePublicTestimony.ts#usePublicTestimonyLetters]] is enabled only while the sheet is open, so the detail poll never downloads hearing bundles ([[mobile-bill-hooks#usePublicTestimonyLetters]]).

## VoteButton

One of the two buttons a user taps to vote on a bill.

- At least 56pt tall, above the 44pt minimum tap area.
- Idle: a card-coloured button with a 2px border and its label in its own vote colour, green for "For" and red for "Against".
- Chosen: a solid fill in the vote colour with whichever of white or dark ink reads better on it. The unchosen button dims once the other choice is recorded or voting is disabled ([[mobile-chrome-and-scroll-layout#Vote buttons wear the vote colour]]).
- Pressing it buzzes the phone once, lightly (Haptics.impactAsync(ImpactFeedbackStyle.Light)), without waiting for the buzz: a haptic call that rejects or throws is swallowed, so it can never stop the vote.
- The label reads "For" or "Against", set in semibold. Its font scaling is capped at 1.3 times, and it shrinks to fit on one line, so "Against" stays inside its half of the row at large type sizes.

Screen-reader wiring. An automated check greps for these props, so they must stay:

- accessibilityRole="button"
- accessibilityLabel=`Vote for ${billTitle}` / `Vote against ${billTitle}`
- accessibilityState={{ selected: active, disabled }}
- accessibilityHint — the exact wording is fixed by the design spec.

### Press-feedback gating

The button visibly reacts while you hold it down, but only while it can still be used. After a vote is cast it is disabled or already selected, and the press feedback does nothing.

## VotePanel

The voting section of a bill's detail screen.

It works the same way as voting on the Bill of the Month screen: two buttons, For and Against. Anyone may read a bill without an account, so the sign-in sheet (AuthPromptSheet) only appears once a signed-out person tries to vote. Casting a vote needs a live connection, which useVote enforces.

The list of props is kept short on purpose, so BillDetailScreen can hand over the `bill` and `user_vote` values exactly as Rails sent them, with no reshaping in between.

### onVoted prop

Runs once a vote goes through, so the parent can reload its data and drop stale copies. Optional: useVote.submit already clears this bill's cached copy by itself.

### className prop

Overrides the space around the panel.

The default "mt-6 mb-2" suits a panel that stands on its own. The Bill tab's hero card passes "mt-2" so the panel tucks under the bill's title block inside the same card, and the Votes tab passes an empty string because its card already supplies the space.

### Caption

A visible sentence under the buttons says why they are in the state they are in, as a polite live region so a change is announced.

One sentence shows at a time, by priority: the recorded vote ("You recorded a For vote on this bill."), then a closed bill (any bill the server reports inactive, whatever its release date), then offline. The error line replaces the caption while it is showing, and carries the server's own message when the server refuses a vote on a closed bill. A disabled button gives a sighted reader nothing to read on its own. The buttons' accessibility hints cover a recorded vote and the offline case; the caption covers all three, and is the only place that says a closed bill is closed ([[user-vote-submission#Disabled mobile vote hints]]).

### Stance restore precedence

Bring back the user's choice when they leave this screen and return.

What the server sent wins. If the server sent nothing, fall back to voteCache, the local copy useVote saves so the app still knows your vote while offline. The Bill of the Month startup payload already carries user_vote, so this mainly covers being offline or arriving before the cache has loaded.
