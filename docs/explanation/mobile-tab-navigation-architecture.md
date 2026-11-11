---
mode: explanation
summary: "Why the mobile app's five bottom tabs each own a native stack, why some screens are registered in more than one stack, and the header/SafeArea conventions shared across them."
status: agent-extracted
related: [mobile-auth-and-onboarding-flow]
---

# Mobile tab navigation architecture

## `AppTabs`

`AppTabs` (`mobile/src/navigation/AppTabs.tsx`) is the five tabs along the
bottom of the app. Each one holds its own set of screens: Home, Bills,
Legislators, Organizations and Profile.

Without explicit `tabBarActiveTintColor`/`tabBarInactiveTintColor`, iOS
defaults the active tab to system blue (`#007AFF`) instead of Sway's blue
(`#3260db`). Every colour on the tab bar comes from the shared design
tokens.

Android gets a little more room than the default in the tab bar, where the
bar otherwise sits cramped against the gesture area at the bottom of the
screen.

`SafeAreaView` keeps content clear of the top and side edges, so nothing
hides under the notch or the Dynamic Island. `"bottom"` is left out of its
`edges` on purpose: the tab bar already leaves room for the home indicator,
and asking for it twice would leave an empty strip.

## `HomeStack` and `BillsStack` share the `BillDetail` route

`HomeStack` (`mobile/src/navigation/HomeStack.tsx`) is the Home tab: the
Bill of the Week, and one bill's detail. The same detail screen is also
registered in `BillsStack`. That is what lets a link to a bill open inside
whichever tab the reader was already in, rather than moving them to
another tab.

`BillsStack` (`mobile/src/navigation/BillsStack.tsx`) is the Bills tab:
the list of bills, and one bill's detail. The detail screen is registered
under the same route name here as it is in `HomeStack`, for the same
reason.

There is no separate "previous bills" screen. The website does not have
one either — its bills page is titled "Past bills" and is the only index
of them. `BillsListScreen` is the equivalent here.

## `LegislatorsStack` and `OrgsStack`

`LegislatorsStack` (`mobile/src/navigation/LegislatorsStack.tsx`) is the
Legislators tab: the list, and one legislator's detail. Both screens live
in the same stack, so tapping a name slides the detail in on top of the
list and swiping back returns to it.

`OrgsStack` (`mobile/src/navigation/OrgsStack.tsx`) is the Organizations
tab: the list, and one organization's detail. Both screens live in the
same stack, so the detail slides in on top of the list and a back swipe
returns to it.

## `ProfileStack`

`ProfileStack` (`mobile/src/navigation/ProfileStack.tsx`) is the Profile
tab, which holds the main profile page plus its six sub-pages. They all
live in the same stack, so each one slides in on top and a back swipe
returns to the page you came from.

### Why the main profile screen is named "ProfileHub"

The screen component is called `ProfileHub` rather than `Profile`, because
the tab holding it is already called "Profile", and React Navigation warns
when one screen sits inside another of the same name. Nobody sees this
name; the tab is what people read.

## `headerOptions.ts`, the shared header settings

`mobile/src/navigation/headerOptions.ts` holds the shared header settings,
mainly for the back button on inner screens.

Every tab (Bills, Home, Legislators, Organizations, Profile) works the
same way: no header on the first screen, and a header on any screen opened
on top of it, carrying a back arrow on a bar the same colour as the page
behind it. Keeping these settings in one file is what stops the five tabs
drifting apart.

## `types.ts`: why the route-name types are split per stack

Types for every navigation screen and the parameters it accepts
(`mobile/src/navigation/types.ts`). Each tab owns its own native stack of
screens, so a deep link like `/bills/:id` opens in the right tab and
screen names from one tab never leak into another. The detail screens
(`BillDetail`, `LegislatorDetail`, `OrgDetail`) are deliberately repeated
across stacks, so moving between tabs pushes the detail screen onto the
stack you started from. React Navigation allows the same screen component
to be registered in several stacks.

The profile stack matches everything the web profile page offers. Saving
an address reassigns the user's district. Theme switching happens inline
on the profile hub screen — there is no separate theme screen.
`DeleteAccount` opens the destructive-action sheet and signs the user out
once the delete succeeds.

`MembershipsList` and `MembershipDetail` live here too. The `tab` param
does the same job as the web `?tab=` query string and is set with
`navigation.setParams`.
