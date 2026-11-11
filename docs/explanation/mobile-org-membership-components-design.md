---
mode: explanation
summary: Design rationale for the mobile organization and membership components — OrgCard, OrgPositionsSection, OrgPreferenceSheet, PositionCard, PositionsList, NewPositionModal, MemberInviteForm, MembersList, MembershipCard, MembershipHeader, PendingChangeCard, PendingChangesList, and PreferenceToggle.
status: agent-extracted
related: []
---

# Mobile organization and membership components

## OrgCard

One organization on a card, with the control for following it.

What the card offers:
- a follow control with three states: Follow, Following, and Member
- the follower count under the locale slug ("N followers" / "1 follower")
- tapping Follow while signed out opens AuthPromptSheet, headed "Sign in to
  follow", rather than calling the server
- a Preferences button that opens OrgPreferenceSheet

Membership comes ONLY from is_member_of_org_ids, never from whether a follow row
exists. A member sees the "Member" label and the "Preferences" button and no way to
unfollow, even when they have no follow row at all.

How it looks:
- the Card supplies the soft shadow (shadowBold), border, corners, and padding
- header: the organization name (2xl semibold) and, when there is one, the locale
  slug (small and muted)
- the follow control sits below the name, with 44px-tall touch targets
- the Card tells screen readers "Open organization {name}"
- testID defaults to `org-card-{id}`

Accessibility: every tappable element carries an accessibilityRole and an
accessibilityLabel. Nothing uses select-none anywhere, which is a project rule.

### Follow-state props

- `initialFollowId` — the follow's id, from user_follows[org.id]. null means signed
  in but not following; undefined means signed out, so we cannot tell either way.
- `isMember` — true when this organization is in the user's is_member_of_org_ids. It
  is true for an active member WHATEVER followId says; membership never depends on
  following. Only supplied when the user is signed in.
- `isSignedIn` — true when the server sent user_follows, which it only does for a
  signed-in user. A signed-out user gets no follow control, and a tap while signed
  out opens AuthPromptSheet.
- `initialPrefs` — the notification settings for this particular follow, from
  user_follow_prefs[org.id]. They fill in OrgPreferenceSheet when the user already
  follows this organization.
- `defaultPrefs` — the user's account-wide defaults for organization notifications,
  from current_user_org_defaults. They fill in OrgPreferenceSheet for a member who
  has NO follow row.
- `onRequestSignIn` — called when the user taps "Sign in" inside AuthPromptSheet. It
  is separate from onDismiss: the caller sends the user to the sign-in screens.
  OrgsListScreen passes navigation.navigate("Auth") in here.

`isFollowing` reads `followId !== null` — -1, the "id not known yet" value, counts as
following.

### Preferences precedence

- `prefSheetOpenNonce` — a counter that goes up each time the preferences sheet
  OPENS. It is used as the sheet's React key, so the sheet is built fresh and reads
  initialPrefs again, without an effect watching whether it is visible. The number
  holds still while the sheet closes, so the slide-out animation still plays.
- `lastSavedPrefs` — remembers what the user saved during this session. The parent
  never fetches user_follow_prefs again after a save, so without this a member with
  no follow row — or someone who has only just followed — would reopen the sheet
  with initialPrefs undefined, every switch would fall back to ON, and whatever they
  had muted would quietly come back.
- `currentInitialPrefs` — what to fill OrgPreferenceSheet with. It must NEVER be
  undefined, because that turns every switch on. Order of preference: what was just
  saved (the freshest), then the server's follow row, then the user's account-wide
  defaults. So a first follow starts from those defaults rather than all-on, and
  pressing Save cannot quietly undo something the user had muted.
- `handlePrefsSave` — save goes to createFollowWithPrefs when the user is a member
  with no follow row, and to updatePreferences otherwise. updatePreferences throws
  while the follow id is still the -1 placeholder, so the sheet shows an error
  instead of a false success. It only sets lastSavedPrefs when the save worked; a
  failure is passed on to the sheet. Holding the saved settings means that reopening
  the sheet before the parent refetches shows them, rather than everything switched
  on.

### Optimistic follower count

`localFollowerCount` keeps the follower count in local state, so following or
unfollowing changes the number at once instead of waiting for a pull-to-refresh. It
starts from org.follower_count, which is what the server said, and resets whenever
the card is rebuilt (see the keyExtractor in OrgsListScreen).

`handleFollowPress` raises the follower count straight away, so the card matches the
server without the user having to pull down to refresh. `handleUnfollowPress` lowers
it straight away, never below zero.

### Follow control states (JSX)

- Follower count sits under the locale slug.
- The follow control. Signed-out users see the Follow button too; tapping it opens
  AuthPromptSheet instead of calling the server.
- The member case, decided by isMember alone and never by followId. A member with no
  follow row still reads as Member. There is no unfollow here, only the Preferences
  button.
- Following but not a member: the button reads "Following", and tapping it unfollows.
- Not following, or signed out: the accent-coloured Follow button. A signed-out tap
  opens AuthPromptSheet, not the API.

### AuthPromptSheet wiring

Shown when a signed-out user taps Follow. onSignIn and onDismiss do different
things: onSignIn closes the sheet AND sends the user to the sign-in screens, through
the onRequestSignIn callback that OrgsListScreen passes down. onDismiss only closes
it, so the user carries on browsing.

### OrgPreferenceSheet wiring

The notification settings for this one organization.
initialPrefs: the real settings for someone who already follows, or the
account-wide defaults for a member with no follow row.
onSave: createFollowWithPrefs for a member with no follow row, and
updatePreferences otherwise; the latter throws while the id is still the
-1 placeholder, which makes the sheet show its error message.
key: the open counter rebuilds the sheet each time it opens, so it reads
initialPrefs again without an effect watching `visible`.

## OrgPositionsSection

Two cards, "Why support" and "Why oppose", holding what
organizations have said about a bill.
[platform] the website lays the two side by side; the app stacks them.
Built from the shared Card, CardHeader, CardTitle, CardContent, and EmptyState pieces.

## OrgPreferenceSheet

The bottom sheet for setting notification preferences for one
organization. It is a React Native Modal that slides up over a see-through backdrop,
the same pattern as AuthPromptSheet.

Inside: three PreferenceToggle rows (new position, support change, summary update), a
choice of how often to hear about them, a Save button, and — only right after a first
follow — a "Skip for now" link.

Accessibility: every tappable element carries an accessibilityRole and an
accessibilityLabel; PreferenceToggle gets its own from ListRow and Switch. All text
stays selectable — nothing uses select-none.

Security: this sheet is never shown to a signed-out user; the caller must check
isSignedIn before rendering it.

### Chips, not a picker

The how-often choice is three tappable chips (Every change / Daily digest /
Weekly digest) rather than a dropdown. React Native has had no built-in Picker since
version 0.55, and @react-native-picker/picker is not a dependency here, because the
project avoids adding packages. The chips do the same job, with the selected one
styled differently. This is a deliberate difference from the website.

### `initialPrefs` contract

Callers MUST pass a COMPLETE set, with all four fields: the server's follow row, the
user's account-wide defaults, or what was just saved. A partial object would quietly
switch its missing event types ON through the fallback below. OrgCard and
OrgDetailScreen always pass a full set (lastSavedPrefs ?? serverRow ?? defaultPrefs).

It is read ONCE, when the sheet is built, into local state. Callers refresh it
by giving the sheet a new `key` each time they OPEN it (see OrgCard and
OrgDetailFollowSection): the rebuild reads initialPrefs again, while keeping the
key steady during the close so the slide-out animation still plays.

### `SHEET_PREF_DEFAULTS`

The one place holding the last-resort values used when a preference field is
missing. Callers are meant to pass a COMPLETE set of preferences (see
OrgPreferenceSheetProps.initialPrefs); these only apply to a field left out.

### Key-rebuild instead of an effect

Local state for the three toggles and the how-often choice is filled from
initialPrefs ONCE when the sheet is built. To refresh those values on the next
open, the caller rebuilds this sheet by giving it a new `key`, rather than
running an effect that watches whether the sheet is visible.

## PendingChangeCard

One proposed change to an organization's position, with buttons
to approve or reject it.

Built from the shared Card. It shows the old and the new summary in two blocks, on
the surface-2 and surface-3 backgrounds. Nothing is struck through; the design keeps
it plain.

Approve calls onApprove straight away — a confirmation sheet would be overkill for
saying yes. Reject opens a DestructiveSheet first, and only calls onReject once
confirmed.

## PendingChangesList

Calls usePendingChanges and lists the results as PendingChangeCard rows. Props:
orgId and membershipId say what to fetch; isAdmin decides whether the Approve
and Reject buttons appear.

## PositionCard

One organization position, shown but not editable.

Built from the shared Card. It shows which bill this is about, a SUPPORTS or OPPOSES
badge, the summary, and a link to the source when there is one.

There is deliberately no way to edit or archive from here; that is still to come.

### `summary_ai_unreviewed`

True when the summary above is a machine's words that no person revised.
A notice then goes under it.

The server sends this beside every position it serializes. Mobile shows
the sentence too, from the same shared copy file the web app reads. A
rule kept on one of the two apps is a rule half the readers never see.

## PositionsList

An organization's positions. Ordinary members just read the list. Organization
admins also get a "Propose new position" button at the top. This component does not
own the modal that opens; the parent (MembershipDetailScreen) does. All this
component does is call the `onProposeNew` callback when the button is pressed.

## NewPositionModal

Where an organization admin proposes a new position on a bill.

It matches the website's NewPositionDialog:
- a full-screen Modal that slides up; on iOS it uses the "pageSheet" style
- a search box and list of bills, limited to the organization's own locale
- a FOR / AGAINST choice made of two buttons side by side, not a switch or a
  segmented control
- a multi-line summary field
- Submit calls useOrgPositions(orgId, membershipId).propose(...)

## MemberInviteForm

The form an organization admin uses to invite someone by email.

NOTE: the Rails membership_invites controller takes `invitee_email`, not a phone
number. The design asked for a phone number, but the server wants an email, so this
form asks for an email.

The caller (MembersList) is what makes sure only admins see this form.

## MembersList

The organization's members, each with a badge showing their role. On the row for
the signed-in user there is a "Leave organization" button, which asks for
confirmation through a DestructiveSheet before doing anything. Admins also get the
MemberInviteForm above the list.

## MembershipCard

One organization membership, built from the shared Card pieces. MembershipsListScreen
uses it in both the Active and the Pending section.

Props:
- variant "active" → a tappable card that opens the membership detail screen
- variant "pending" → a card with Accept and Decline buttons inside; those buttons
  do nothing unless the caller passes onAccept and onDecline

### `COPY` (wording duplicated for now)

Wording kept here for now. The same strings live in parityCopy.ts and match exactly;
a later cleanup will import them from there instead.

## MembershipHeader

The app's version of the website's app/frontend/components/organizations/MembershipHeader.tsx.
It shows the organization's name, a badge with your role, and how many members there
are. Anything passed as children renders below the header; MembershipDetailScreen
uses that to drop in its tab strip.

### Two organization shapes

Accept the organization in either form:
- useMembership hands back { membership: { ..., organization: {...} } }
- or the caller passes the organization on its own, as the admin path does

## PreferenceToggle

One settings row with a switch on the right.

It uses the shared `ListRow` in its static form — no chevron, and the row itself is
not tappable — with a native React Native `Switch` in the row's rightSlot.

It replaces an earlier hand-built shape (a Pressable with its own Text and Switch),
so notification toggles get the same row furniture — label, description line,
padding, border — as every other settings row in the app.

Used by:
- NotificationPrefsScreen, for its four notification toggles

How it looks:
- a touch target at least 44pt tall, inherited from ListRow.
- Open Sans: a 16pt label with a 14pt muted description under it.
- the Switch sits at the right-hand end of the row.

Accessibility:
- a React Native Switch already announces itself as a switch.
- accessibilityState={ checked: value, disabled } on the Switch, so a screen
  reader says whether it is on or off rather than only reading the row label.

### About `disabled`

The `useNotificationPrefs` hook does NOT report which single
preference is mid-save, and it puts the value back itself when a PATCH fails.
Callers that track that themselves may pass `disabled` in, but PreferenceToggle
never touches the hook.

## Empty catch blocks: error already held by the hook

`MemberInviteForm.handleSubmit` and `NewPositionModal.handleSubmit` both catch and
do nothing beyond that: the hook (`useMemberInvite`, `useOrgPositions`) already
holds the error and the form/modal reads it from there, and in NewPositionModal's
case the modal stays open so the user can retry.
