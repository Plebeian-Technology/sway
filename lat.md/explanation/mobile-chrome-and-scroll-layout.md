---
lat:
  mode: explanation
---

# Mobile chrome and scroll layout

Why the phone app pins a single slim brand header, scrolls every filter together with its list, and draws its colour from the Sway primary blue instead of grey on white.

## Brand band colours

The header band, the strip behind the status bar and the drawer's brand block share one colour: the primary blue in light mode and the deep blue surface in dark mode.

[[mobile/src/theme/chrome.ts#chromeColors]] derives both colours from [[mobile/src/theme/tokens.ts]] instead of adding tokens. That file is generated from the web theme and a contract test pins its key set, so a mobile-only token would either break the test or drift from the web.

White text wins the contrast check on both bands. In dark mode the band is a close cousin of the page ground, so a 2px primary edge along its lower side keeps it reading as a coloured bar.

## The pinned header is one 56pt row

[[mobile/src/components/BrandHeader.tsx#BrandHeader]] is a single row at least [[mobile/src/components/BrandHeader.tsx#BRAND_HEADER_MIN_HEIGHT]] tall: menu button, a 32pt logo and the title.

The earlier header held a 60pt logo with 16pt of padding above it, which cost about 84pt before any content. A minimum height rather than a fixed one lets the title wrap to a second line at large text sizes without clipping.

The header and an offline banner together stay under a quarter of a 667pt iPhone SE screen. A test pins that budget, so a later change that grows the header fails loudly.

## Filters live inside the list, not above it

Search, sort, category, locale and session controls are the list's header component, so they scroll away with the rows and the pinned area is only the brand header.

Before this change those controls were siblings of the list. On the Bills screen they added up to roughly 500pt, which left about a quarter of an iPhone SE for the bills themselves. Shrinking each control would not have fixed that, because the cost was that nothing could scroll out of the way.

The header is passed as an element, not as a component function. A function created on each render is a new component type every time, so React unmounts the search box on every keystroke and the keyboard drops. An element keeps the same input mounted.

The list also sets `keyboardShouldPersistTaps="handled"`, so a tap on a sort chip works while the keyboard is open. The header spans the full width, so each row wraps itself in 16pt of horizontal padding instead of the list container doing it.

Screens that sometimes show a message instead of a list, such as the legislator history states, put the same header at the top of a scroll view so the controls stay reachable.

Controls that scroll away are a long trip back on a paginated list, so on the Bills list a tap on the title in the pinned brand header scrolls the list to the top. [[mobile/src/components/BrandHeader.tsx#BrandHeader]] takes this as an opt-in `titleAction`, which carries its own accessibility label, so every other screen keeps a plain heading with nothing to tap. The Bills loading state omits it too, because no list is mounted yet.

A sticky search field would have taken back the height that moving the controls into the list freed on small phones. React Navigation's `useScrollToTop` does not help here: it listens for a press on a tab navigator's tab, and the Bills stack sits in a drawer, which never sends that event.

## The brand band runs up under the status bar

A coloured view as tall as the top safe-area inset sits above the drawer, and the safe-area view below it guards only the other three edges.

The inset becomes a height where it used to be padding, so the space above the drawer is the same size and the drawer panel's padding compensation in [[mobile-tab-navigation-architecture#AppDrawer#Drawer panel padding comes from the root SafeAreaView]] is written for this arrangement too. No automated test measures it, because the test environment reports a zero inset.

Pushed screens use the same band colour for the native stack header through [[mobile/src/navigation/headerOptions.ts#pushedScreenOptions]], so the top of the screen looks the same on every page. The status bar text is fixed to light, because the band is dark enough for light text in both appearances.

## The drawer panel opens with a brand block

The drawer starts with a rounded card in the band colour holding the logo, the name and the tagline, and its active item is a filled primary pill.

A plain list of icons and labels on a white card gave little sign of where the reader was. A filled pill for the current section mirrors the web sidebar, where the current page is the one item in the primary colour.

## Buttons are filled with the brand colour

The default and destructive buttons are solid fills with a same-colour 1px border, and the outline button is a pale blue tint with a 2px primary border.

Every variant used to carry a 2px grey border. A grey frame around a blue fill made each button look half disabled and gave the screen no colour at all. The ghost variant stays transparent and shadowless.

## Cards carry a coloured edge

A card can take an accent colour, drawn as a 5px strip on its left edge. Bill cards use the reader's own vote colour when they have voted and the primary blue otherwise, and legislator and organization cards use the primary blue.

Card padding dropped from 24pt to 16pt and the gap from 24pt to 12pt, because three cards per screen was too few. The bill card now shows the headline, two lines of summary and both vote counts in one row, while the whole card stays the tap target and the "Open bill" button remains for screen reader and switch users.

## Vote buttons wear the vote colour

An unchosen vote button is a white button outlined in its own colour, green for For and red for Against, and the chosen one fills solid with whichever text colour reads best on it.

When the reader has already voted, the unchosen button dims instead of keeping full strength, so the recorded choice is the one that stands out.

## Profile rows are grouped cards with icon tiles

The profile page pins its header, then shows an identity card and two grouped cards of rows, each row led by a tinted icon tile and trailed by a primary chevron.

Grouping the rows into rounded cards with section captions replaces one long grey list, and the destructive rows keep the destructive colour on both the icon and the label.
