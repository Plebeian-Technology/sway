---
mode: reference
summary: "The three-tier CSS variable contract every Sway theme file must declare, checked by token-contract.test.ts."
status: agent-extracted
related: [docs/explanation/theme-test-suite-silent-failure-guards.md]
---
<!-- vale Vale.Spelling = NO -->

# Theme variable contract

`app/frontend/styles/themes/__tests__/token-contract.test.ts` is the
reference for Sway's theme variables. Every theme file at
`app/frontend/styles/themes/<name>.css` MUST declare exactly the set of
variables below — no more, no fewer — in each of its blocks.

A theme restyles the whole app, not just its colours: colour, type, spacing,
corner shape, divider lines, texture and motion. The variables fall into
three tiers, decided by WHERE in a theme file they have to be declared:

| Tier | Meaning | Declared in |
| --- | --- | --- |
| `MODE_VARIANT` | Value differs between light and dark | The base block, the `.dark` block, and the `@media auto` block (3 places) |
| `MODE_INVARIANT` | One value per theme, the same in light and dark | The base block only |
| `INTENSITY` | Replaced by `[data-intensity="bold"\|"calm"]` | The base block (the default) AND every `[data-intensity]` block (light/dark/auto x bold/calm) |

The base block's selector is `[data-theme="<name>"]`; the test removes the
`[data-theme="…"]` part so matching blocks from different themes line up.

## Tier 1: `MODE_VARIANT` (colour)

Declared in the base block, `.dark`, and `@media auto`:

`--background`, `--foreground`, `--card`, `--card-foreground`, `--popover`,
`--popover-foreground`, `--primary`, `--primary-foreground`, `--secondary`,
`--secondary-foreground`, `--muted`, `--muted-foreground`, `--accent`,
`--accent-foreground`, `--destructive`, `--border`, `--border-soft`,
`--border-strong`, `--input`, `--ring`, `--success`, `--success-foreground`,
`--warning`, `--warning-foreground`, `--info`, `--info-foreground`,
`--surface-1`, `--surface-2`, `--surface-3`, `--vote-for`, `--vote-against`,
`--muted-icon`, `--avatar-border`, `--chart-muted`, `--scrim`.

## Tier 2: `MODE_INVARIANT` (base block only)

- **TYPE** — one font for headlines and one for body text, a set of sizes
  named by the job they do, plus weights, line heights and letter spacing.
  `--font-numeric` holds a `font-variant-numeric` value for vote tallies and
  scores: `--font-display`, `--font-body`, `--font-numeric`,
  `--type-display`, `--type-h2`, `--type-h3`, `--type-lede`, `--type-body`,
  `--type-small`, `--type-micro`, `--type-stat`, `--weight-body`,
  `--weight-medium`, `--weight-bold`, `--weight-display`,
  `--leading-display`, `--leading-heading`, `--leading-body`,
  `--tracking-display`, `--tracking-body`, `--tracking-caps`.
- **DENSITY** — one spacing unit (Tailwind's `--spacing` is built from it,
  so every `p-*`/`m-*`/`gap-*` class restyles across the whole app without
  editing a single component), the comfortable line width for reading, the
  outer page width, and the size of buttons and inputs: `--space-unit`,
  `--measure`, `--content-max`, `--control-height`, `--control-height-sm`,
  `--control-pad-x`.
- **SHAPE** — the main corner radius plus two smaller ones. Each is written
  out rather than worked out with `calc()`, because the chamber design's
  corner sizes are not in proportion to each other. `--radius` stays the
  main variable so the roughly 25 places that already call `var(--radius)`,
  and Tailwind's `--radius-lg` mapping, need no changes: `--radius`,
  `--radius-sm`, `--radius-md`.
- **RULE** — how thick divider lines are (separate from the border COLOR
  variables above) plus their style (solid / double / dashed):
  `--rule-hair`, `--rule-mid`, `--rule-thick`, `--rule-style`.
- **TEXTURE** — a `background-image` value for the page itself; `none` for
  themes that carry no grain: `--texture-page`.
- **MOTION** — how long interactions take, the easing curve for small
  movements, the one calm easing curve for a page arriving, and an app-wide
  multiplier (`--motion-scale: 0` turns motion off): `--dur-1`, `--dur-2`,
  `--dur-3`, `--ease-out`, `--ease-entrance`, `--motion-scale`.

## Tier 3: `INTENSITY`

Declared in the base block plus every `[data-intensity]` block:
`--neo-border-width`, `--neo-shadow`.

## Mobile's twin: `swayTokens`

`mobile/src/theme/tokens.ts`'s `swayTokens.light` and `swayTokens.dark`
carry the same 35 Tier-1 keys as this contract (camelCased:
`mutedIcon`, `avatarBorder`, `chartMuted`, `scrim`, and so on), checked by
`mobile/__tests__/theme/tokens.test.ts`. `destructiveForeground` is left
out on purpose on both sides: the matching `--destructive-foreground`
token is absent from this contract too.

`mobile/src/theme/effects.ts`'s `shadowBold` diverges from the web
stylesheet's shadow values on purpose: `sway.css` uses opacity `.075` with
a 2px radius, which is invisible on a phone, so mobile's light mode uses a
still-soft `.10` with a 6px radius.

### Where `effects.ts`'s shadow values come from

`effects.ts` follows the web stylesheet: in light mode
`--neo-shadow = 0 0.125rem 0.25rem rgba(0,0,0,.075)`. In dark mode the base
`[data-theme="sway"].dark` block does NOT redeclare `--neo-shadow`, so it
inherits that same light `rgba(0,0,0,.075)` value. The `0.5` opacity and
`.5rem` blur show up only in the bold dark variant,
`[data-theme="sway"].dark[data-intensity="bold"]`, and the dark numbers in
`shadowBold()` follow that bold dark shadow: opacity `0.5`, radius `4`. The
calm version of `--neo-shadow` is `none`. The values come from
`app/frontend/styles/themes/sway.css`, the `[data-theme="sway"]` block.
`[platform]`: Android honours `elevation` only and ignores `shadowColor`
and the rest.

`[platform]`: the web's exact `rgba(0,0,0,.075)` with a 2px blur is all but
invisible on a phone. A white card on the `#f7f9fc` background would be
set apart only by a 1px border of almost no contrast, and a phone has no
hover state to make up for it. So the light shadow is lifted to something
still soft but actually visible: opacity `.10`, 6px blur. That changes how
it renders, NOT the brand values — colours, type and corner radius all
still come straight from `sway.css`.

### Why `pressFeedback` exists

`Pressable`, `Card`, `VoteButton`, and `ListRow` used to fire a haptic on
press but showed no visual change at all — the single most common sign of
an app that was not built for touch. `pressFeedback` (`effects.ts`)
returns a small scale-down and opacity dip, applied as an inline `style`
(not a className) so it composes with NativeWind classes and the shadow
style array. It happens instantly, with no spring animation, so it stays
reliable under the reanimated test mock and looks crisp on a real device.
It returns `null` when not pressed or disabled, so callers can drop it
straight into a style array.

### Why `tokens.ts` omits spacing

`mobile/src/theme/tokens.ts` is auto-generated by
`scripts/extract_sway_tokens.mjs` from `sway.css`. Spacing tokens are
intentionally omitted from that output — CSS rem units are inert in React
Native (silently 0). RN unitless dp values or NativeWind spacing classes
are used instead. That header is generator-owned; re-run
`pnpm mobile:tokens` after touching `sway.css` rather than editing
`tokens.ts` by hand.

### `ThemeProvider`'s theme-mode context

`mobile/src/theme/ThemeProvider.tsx` holds the mode the user chose, and the
light/dark value that follows from it:

- `mode`: what the user picked — `"auto"`, `"light"`, or `"dark"` —
  defaulting to `"auto"`
- `colorScheme`: the actual `"light"` or `"dark"` value this works out to;
  this is what NativeWind's `colorScheme` prop reads
- `setMode`: changes `mode` IN MEMORY only here. Saving the choice to the
  server happens in `useThemeSync`, which sends
  `PATCH /users/preferences` and then calls this setter with the confirmed
  value.

`"Auto"` means follow `useColorScheme()` (the phone's own light/dark
setting). `"Light"` and `"Dark"` override it.

On first mount, if the user is signed in, `ThemeProvider` reads
`bootstrap.current_user.theme_mode` and starts `mode` from it, so the
screen already matches the saved preference instead of flashing `"auto"`
first. `BootstrapContext` is not required for this to work — if it is
missing (an early splash screen, or a test), this quietly falls back to
`"auto"`. `readBootstrapModeSafely` avoids a static top-of-file import of
`useBootstrap`, because tests render `<ThemeProvider>` with no
`BootstrapProvider` around it, and the fallback should be quiet rather than
throw.

The web defaults to `"light"` mode (see
[Theme mode and theme id resolution](../explanation/theme-mode-and-theme-id-resolution.md)
for how the server resolves it there), but mobile keeps `"auto"`:
following the system setting is the normal pattern on iOS and Android, and
a phone's own theme is a more reliable signal than it would be on a
laptop. If the server does send back a literal `"light"` or `"dark"`, that
value is honored as given; only a missing or empty field falls back to
`"auto"`.
