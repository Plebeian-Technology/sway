---
lat:
  mode: explanation
---

# Mobile shared primitives

Design rationale for mobile's shared UI primitives — ui/Card, ui/EmptyState, ui/FadeInItem, ui/FormField, ui/ListRow, ui/Pressable, ui/SegmentedControl, SkeletonCard, StampedBadge, BrandHeader, and BroadsideTabStrip.

## BrandHeader

The shared row holding the logo and the page title.

It is for screens with no navigation bar of their own: the first screen of a tab, and dead-end states. Screens pushed onto a stack get the logo from `pushedScreenOptions().headerTitle` instead.

The point is that every screen reads as "Sway · {title}", so the logo shows up all through the app rather than only on the sign-in screen and pushed detail screens.

The header is one coloured row with a 32pt logo, smaller than the brand block inside AuthScreen.tsx, so that it costs little height; see [[mobile-chrome-and-scroll-layout#The pinned header is one 56pt row]].

The menu button that opens the drawer is opt in through `onMenuPress`, so DeviceUnsupportedScreen keeps the plain row, and while it shows the title takes the remaining width and wraps instead of clipping on an iPhone SE.

The title is a plain heading unless the screen passes `titleAction`, which wraps it in a 44pt button. That button is a row, so the title keeps its `flex-1` width and wraps as it does without one. A Pressable is one accessible element, so the heading role inside it is folded into the button: a screen reader announces a button whose label includes the title, and heading navigation cannot reach the title on that screen. That is the accepted cost of making the title tappable.

The menu button is a 44pt square, and the shared Pressable base padding of `px-4 py-2` would leave its content box 12pt wide for a 24pt icon. The button clears that padding with `!px-0 !py-0`. The plain `px-0 py-0` would not work: NativeWind settles two utilities that set the same property by their order in the generated stylesheet, not by their order in `className`, and Tailwind emits `px-0` before `px-4`. The important modifier outranks stylesheet order.

## BroadsideTabStrip

A row of tabs written by hand, with a 3px primary-blue underline beneath the tab you are on and the active label in the same blue.

Accessibility:

- the strip itself is marked accessibilityRole="tablist"
- every tab is marked accessibilityRole="tab", NOT the default "button"
- the active tab carries accessibilityState={{ selected: true }}
- the others carry accessibilityState={{ selected: false }}

Each label stays on one line: its font scaling is capped at 1.3 times and it shrinks down to 75% to fit, so the longest bill-screen label, "Summaries", stays inside its third of the strip at large type sizes.

### No animation

None needed.

The underline is a plain View shown or hidden under each label, not one bar that slides between tabs. A sliding bar would need an Animated.Value, but the design asks for an underline per tab, and this way the whole component stays around 20 lines.

No new packages — React Native built-ins and NativeWind only.

## StampedBadge

A small, solid, pill-shaped status label.

The look copies the badge in the web app's sway.css: a solid background in whatever status color the caller passes in, a 4px corner radius (the --radius-sm design token), and a 1px border in the same color as the fill so the edge stays crisp. Numbers use tabular figures so they line up in columns. The text color is chosen for you: white (#ffffff) or dark ink (#212529), whichever has the HIGHER contrast ratio against the fill under WCAG, the web accessibility standard for readable text.

An older design drew a stamped ring with a 12%-opacity color wash instead of a solid fill. That design is retired; do not bring the inset ring or the wash back — the acceptance criteria describing them are stale.

A bill's badge takes its color from the active color scheme, and the server allows only four statuses: passed, failed, committee and vetoed. [[mobile/src/utils/billStatus.ts#billStatusColor]] picks the token and [[mobile/src/utils/billStatus.ts#billStatusLabel]] capitalises the label. Light-mode fills are deep inks, so white text wins; dark-mode fills are pale tints, so dark ink wins:

| Status | Token | Light fill | Light: white vs dark ink | Dark fill | Dark: white vs dark ink |
| --- | --- | --- | --- | --- | --- |
| Passed | success | `#1f7a45` | 5.35:1 vs 2.89:1, white | `#6dd7a0` | 1.77:1 vs 8.73:1, dark ink |
| Failed / Vetoed | destructive | `#c62b38` | 5.52:1 vs 2.79:1, white | `#f08d94` | 2.35:1 vs 6.57:1, dark ink |
| Committee | warning amber | `#8a5a00` | 5.93:1 vs 2.60:1, white | `#ffd600` | 1.41:1 vs 10.92:1, dark ink |
| Any other status | muted-foreground | `#636b73` | 5.41:1 vs 2.85:1, white | `#adb5bd` | 2.07:1 vs 7.43:1, dark ink |

The caller chooses the color, so other badges reuse the component: the constituent-letter cards color their stance badge from the success, destructive and muted-foreground tokens. The badge is one accessible element that reads "Status: {label}" unless the caller passes another word as `accessibilityPrefix`; the constituent-letter cards pass "Position", because a stance is not a status.

Text-color rule: `contrast("#ffffff", fill) >= contrast("#212529", fill) ? "#ffffff" : "#212529"`

### readableForeground

[[mobile/src/components/StampedBadge.tsx#readableForeground]] returns whichever of `"#ffffff"` or `"#212529"` has the higher WCAG 2.1 relative-luminance contrast ratio against `fill`.

[[mobile/src/components/StampedBadge.tsx#parseRGB]] parses `"#rrggbb"` or `"rgb(...)"` strings into `0–255` channel tuples and returns `null` for any other format so [[mobile/src/components/StampedBadge.tsx#readableForeground]] falls back to `"#ffffff"` without throwing.

Picks checked by hand against the current palette and the blue chosen for the mobile theme:

| fill | wins | contrast (white vs dark) |
| --- | --- | --- |
| `#8a5a00` | `#ffffff` | 5.93 vs 2.60 |
| `#c62b38` | `#ffffff` | 5.52 vs 2.79 |
| `#3260db` | `#ffffff` | 5.48 vs 2.81 |
| `#636b73` | `#ffffff` | 5.41 vs 2.85 |
| `#1f7a45` | `#ffffff` | 5.35 vs 2.89 |

## SkeletonCard

This gently pulsing grey block is the standard loading placeholder for list and detail screens.

In [[mobile/src/components/SkeletonCard.tsx#SkeletonCard]], `heightClass` defaults to `"h-24"` (about 96pt) to match the height of a bill card. If it turns out to feel wrong once people use the app daily, the planned alternative is to show the last cached data at once, with a quiet marker saying how fresh it is. That option is written down here so nobody has to go hunting for the reasoning.

## ui/Card

The mobile twin of the web card at app/frontend/components/ui/card.tsx.

How it should look is fixed by the shared design spec. Style class names here name both themes out loud (the NW4 syntax): bg-{token}-light dark:bg-{token}-dark. Pass the shadow through style={shadowBold(colorScheme)}, never through className — that is a known trap on this stack. The card title is marked as a header, so a screen reader can move from card to card by heading.

## ui/EmptyState

The one block every mobile screen uses to say "nothing here yet" or "no results".

How it should look is fixed by the shared design spec. Copied from the hand-rolled empty state in mobile/src/screens/BillsListScreen.tsx and the "no results" block in app/frontend/pages/Bills.tsx. There is no shared web version yet; writing one was put off to a later clean-up pass on purpose.

### Default icon

A lone line of text looks like the screen failed to finish loading, so show a faint icon above it to give the eye something to land on. Callers can pass their own `icon`. The thin stroke and muted color keep it quiet.

### Compact variant

The `compact` prop fits a block inside a Card, such as the bill detail retry row, where the full-page padding looks out of proportion.

It swaps the container padding from `py-12` to `py-4` and the default icon from 40 pt to 24 pt. The title, body and button are unchanged, and the button keeps its 44 pt minimum height from [[mobile/src/components/ui/Pressable.tsx#Pressable]]. The default stays the full-page layout.

## ui/FadeInItem

Wraps a list row or card so it fades in, each one slightly after the one above it.

Mobile lists used to snap into place with no transition. A short fade-and-rise on each row gives the "content settling in" feel people expect from a native app, both when data first arrives and when rows appear during scrolling. The delay grows with the row's position but stops growing after a few steps, so the first screenful staggers nicely while rows further down — and rows that re-appear during a fast scroll — show up right away instead of waiting on an ever-longer delay.

The animation library already respects the phone's "Reduce Motion" setting for entrance animations, so anyone with that turned on sees rows appear instantly.

This is the only entrance animation in the app: a fade plus a small rise, no zooming or bouncing. It keeps the app calm rather than busy.

## ui/FormField

The one mobile text input: a label above, the box, and an error message below when something is wrong.

How it should look is fixed by the shared design spec. Modelled on the hand-rolled input in mobile/src/screens/PhoneEntryScreen.tsx. No drop shadow — the design spec wants form fields flat.

## ui/ListRow

The standard single row used by settings screens and lists on mobile.

How it should look is fixed by the shared design spec. Modelled on [[mobile/src/components/LegislatorCard.tsx#LegislatorCard]], which set the pattern for the press handling and the screen-reader wiring. An optional `description` prop in [[mobile/src/components/ui/ListRow.tsx#ListRowProps]] renders a muted second line beneath `label` — used by [[mobile/src/components/PreferenceToggle.tsx#PreferenceToggle]] to explain what each notification switch controls — while omitting it keeps the single-line row shape.

Rows respond to a plain tap only: no swipe gestures, no long-press. That is a deliberate choice to keep the app simple. Rows are flat. Only cards get a drop shadow.

## ui/Pressable

The mobile twin of the web button at `app/frontend/components/ui/button.tsx`.

How it should look is fixed by the shared design spec. Four looks: `default | destructive | outline | ghost`. The first two are solid fills with a 1px border in their own colour, `outline` is a surface3 tint with a 2px primary border, and `ghost` is transparent ([[mobile-chrome-and-scroll-layout#Buttons are filled with the brand colour]]). Every button in [[mobile/src/components/ui/Pressable.tsx#Pressable]] is at least 44pt tall, set by an inline `minHeight`. That is Apple's floor for a tap target in its Human Interface Guidelines. The shadow comes from [[mobile/src/theme/effects.ts#shadowBold]]. The `ghost` look has no shadow at all. Its `accessibilityRole` defaults to `"button"` and can be overridden with `"checkbox"` for filter chips or `"link"` for external URLs. A press buzzes the phone once, lightly, before the caller's `onPress` runs.

### Haptic feedback is fire-and-forget

One light buzz on tap — the app's only kind of haptic feedback. Started and forgotten: if the buzz fails, the press still goes through. SegmentedControl and the vote buttons start their own buzz the same way ([[mobile-bill-surface-components-design#VoteButton]]).

## ui/SegmentedControl

The row of joined buttons iOS and Android use to switch between a few views.

\[platform]: this is on purpose different from the web app, which uses a strip of tabs with an underline (app/frontend/components/ui/tabs.tsx). It is the first segmented control in mobile/src — nothing here did this before, so there was no in-house pattern to copy. It follows the way iOS and Android do segmented controls, as written down in the design spec:

- Every segment is the same width (flex-1 each) inside one rounded box
  (the surface3 tint with a 1px primary border, and the `rounded-xl` corner size,
  defined in tailwind.config.js under borderRadius.xl).
- Each segment is at least 44pt tall (44dp on Android), the same minimum
  tap height that ui/Pressable.tsx enforces with style={{ minHeight: 44 }}.
- The chosen segment gets a solid fill in the `primary` color. NativeWind
  spells that color `accent` — see "accent: dual('primary')" in
  tailwind.config.js. Its label color comes from
  StampedBadge.readableForeground, so the contrast maths lives in one place
  instead of being worked out again here.
- The other segments have no background and normal foreground text.
- For screen readers the outer box is a "tablist" and each segment is a
  "tab" that reports whether it is selected. On the web the Radix tabs
  library does this automatically; here we say it by hand.

Built from plain React Native Pressable and View. No new npm or Expo package, because the project sticks to what the free tier gives us.
