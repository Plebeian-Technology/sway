---
lat:
  mode: explanation
---

# Mobile drawer navigation architecture

Why the mobile app's five drawer items each own a native stack, why some screens are registered in more than one stack, and the header/SafeArea conventions shared across them.

## AppDrawer

`AppDrawer` ([[mobile/src/navigation/AppDrawer.tsx]]) is a left drawer with five items. Each one holds its own set of screens: Home, Bills, Legislators, Organizations and Profile.

Five labelled items fit in a drawer at any screen size, where a bottom bar on a small phone such as the iPhone SE clips its labels against the bottom of the screen.

Deep links, the onboarding handoff and calls such as `navigate("Legislators")` address the items by their route names: `Home`, `Bills`, `Legislators`, `Orgs` and `Profile`.

Each item carries a test id through `drawerItemTestID` (`drawer-item-home`, `drawer-item-bills`, `drawer-item-legislators`, `drawer-item-orgs`, `drawer-item-profile`), so Maestro flows tap an item by id rather than by its label.

Every colour comes from the shared design tokens: the active item is a filled `primary` pill with `primaryForeground` text, inactive items use the `foreground` colour, and the drawer itself sits on `card` beneath a brand block ([[mobile-chrome-and-scroll-layout#The drawer panel opens with a brand block]]). Without them, React Navigation falls back to its own blue and grey. The scene background is set to the `background` token for the same reason, because `NavigationContainer` is given no theme.

The drawer's own header is hidden. Each top level screen renders [[mobile/src/components/BrandHeader.tsx#BrandHeader]] with a menu button that opens the drawer, including in its loading and empty states, so the menu is reachable before any data arrives.

A view in the brand band colour, as tall as the top inset, covers the top edge, and `SafeAreaView` guards the other three. Nothing else in the layout leaves room for the home indicator. See [[mobile-chrome-and-scroll-layout#The brand band runs up under the status bar]].

The drawer library stays on 7.13, and an override in [[mobile/pnpm-workspace.yaml]] holds its shared header package at 2.9.40, the release the native stack already uses. Later releases of both declare a newer navigation core than the app's 7.3 as a peer, and drawer 7.14 crashed on mount from that mismatch.

### Drawer panel padding comes from the root SafeAreaView

The drawer panel sits inside the root `SafeAreaView`, so its content is already clear of the notch, the home indicator and the side edge.

The drawer library's own content list adds the device insets as padding a second time, on top of a 12pt spacing. It reads the insets from the safe-area context, and a `SafeAreaView` pads its own children without changing the insets that context reports to them. Left alone, the panel would carry a double gap at the top and bottom. `drawerContentContainerStyle` sets all four paddings back to the library's 12pt spacing, which leaves the root `SafeAreaView` as the only source of the inset.

### Edge swipe opens the drawer only on top level screens

A swipe from the left edge opens the drawer on the first screen of each stack, and on the second Home and Bills routes that show the same top level screens.

On a pushed screen such as Bill Detail, the same edge swipe is the iOS back gesture. If the drawer also listened there, the swipe would open the drawer instead of returning to the list. Each drawer item reads the focused route inside its stack and turns swiping off once a pushed screen is in front. Before a stack has reported any state, the focused route is unknown; that only happens while the stack shows its first route, which is always top level.

## HomeStack and BillsStack share the BillDetail route

`HomeStack` (`mobile/src/navigation/HomeStack.tsx`) is the Home drawer item: the Bill of the Month, and one bill's detail.

The same detail screen is also registered in `BillsStack`. That is what lets a link to a bill open inside whichever section the reader was already in, rather than moving them to another one.

`BillsStack` (`mobile/src/navigation/BillsStack.tsx`) is the Bills drawer item: the list of bills (`BillsList` and `PastBillsOfTheMonth`), and one bill's detail. The detail screen is registered under the same route name here as it is in `HomeStack`, for the same reason.

`BillsListScreen` serves both "All Bills" (`/bills`) and "Past Bills of the Month" (`/past_bills_of_the_month`) via an in-screen `SegmentedControl`, with `PastBillsOfTheMonth` registered in `BillsStack` so universal links to `/past_bills_of_the_month` open directly on the Past Bills of the Month segment.

## LegislatorsStack and OrgsStack

`LegislatorsStack` (`mobile/src/navigation/LegislatorsStack.tsx`) is the Legislators drawer item: the list, and one legislator's detail.

Both screens live in the same stack, so tapping a name slides the detail in on top of the list and swiping back returns to it.

The stack also registers the shared bill detail route, so a bill tapped in a legislator's Bill of the Month voting record opens inside the Legislators section and back returns to that legislator. Because a bill can now sit inside this stack, the bill screen's compare-with-representatives action targets the list route and pops back to it, rather than only switching sections, which would leave the reader on the bill.

`OrgsStack` (`mobile/src/navigation/OrgsStack.tsx`) is the Organizations drawer item: the list, and one organization's detail. Both screens live in the same stack, so the detail slides in on top of the list and a back swipe returns to it.

## ProfileStack

`ProfileStack` (`mobile/src/navigation/ProfileStack.tsx`) is the Profile drawer item, which holds the main profile page plus its six sub-pages.

They all live in the same stack, so each one slides in on top and a back swipe returns to the page you came from.

### Why the main profile screen is named "ProfileHub"

The screen component is called `ProfileHub` rather than `Profile`, because the drawer screen holding it is already called "Profile", and React Navigation warns when one screen sits inside another of the same name.

Nobody sees this name; the drawer label is what people read.

## headerOptions.ts, the shared header settings

`mobile/src/navigation/headerOptions.ts` holds the shared header settings, mainly for the back button on inner screens.

Every drawer item (Bills, Home, Legislators, Organizations, Profile) works the same way: no header on the first screen, and a header on any screen opened on top of it, carrying a white back arrow on a bar in the brand band colour. [[mobile/src/navigation/headerOptions.ts#pushedScreenOptions]] renders the Sway logo in the header center with `headerTitleAlign: "center"` (so Android does not left-align it) and colors the back arrow white against the band. Keeping these settings in one file is what stops the five stacks drifting apart.

## types.ts: why the route-name types are split per stack

Types for every navigation screen and the parameters it accepts (`mobile/src/navigation/types.ts`).

Each drawer item owns its own native stack of screens, so a deep link like `/bills/:id` opens in the right section and screen names from one stack never leak into another. The detail screens (`BillDetail`, `LegislatorDetail`, `OrgDetail`) are deliberately repeated across stacks, so moving between sections pushes the detail screen onto the stack you started from. React Navigation allows the same screen component to be registered in several stacks. `PreviousBills` is omitted from [[mobile/src/navigation/types.ts#BillsStackParamList]] because mobile serves past featured bills through `PastBillsOfTheMonth` on `BillsListScreen` rather than a separate screen.

The profile stack matches everything the web profile page offers. Saving an address reassigns the user's district. Theme switching happens inline on the profile hub screen — there is no separate theme screen. `DeleteAccount` opens the destructive-action sheet and signs the user out once the delete succeeds.

`MembershipsList` and `MembershipDetail` live here too. The `tab` param does the same job as the web `?tab=` query string and is set with `navigation.setParams`.
