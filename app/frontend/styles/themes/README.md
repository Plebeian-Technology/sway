# Sway themes

A theme re-skins the whole application. Each theme commits to light **or** dark —
the mood is part of the theme's identity, not a toggle.

## The registry

`index.ts` lists every theme; `sway` is the default. `ThemeId` here and
`ThemeHelper::VALID_THEME_IDS` in `app/helpers/theme_helper.rb` are two hand-kept
copies of one list. Nothing generates either from the other.
`__tests__/allowlist-sync.test.ts` checks that they agree — keep it passing when
you add or remove a theme.

| id | file | notes |
|---|---|---|
| `sway` | `sway.css` | **Default.** Light. A faithful reproduction of the real pre-redesign app (Bootstrap 5): Sway blue `#3C6EF7`, Open Sans weight 300, background `#f7f9fc`, ~5px radius, soft grey shadows. Formerly `legacy-v2`. |
| `banner` | `banner.css` | **Hidden.** See below. |
| `ballot` | `ballot.css` | Barlow Semi Condensed / Barlow. |
| `cornerstore` | `cornerstore.css` | Libre Franklin. Note the spelling — no trailing `n`. |
| `monochrome` | `monochrome.css` | Inter / IBM Plex Mono. Printing ink on paper, zero hue. |
| `service-manual` | `service-manual.css` | Light. Inter / IBM Plex Mono. GOV.UK / USWDS civic reference manual aesthetic. |
| `swiss-grid` | `swiss-grid.css` | Inter / IBM Plex Mono. Swiss federal bulletin aesthetic with hairline grid and signal red. |

### Banner is hidden, not removed

`banner` carries `hidden: true` in the registry, so it stays out of the picker.
Everything about it still works — colours, layouts, validation, both copies of
the allowlist. Removing the flag re-lists it.

It is a contemporary local-newsroom skin modelled on
[The Baltimore Banner](https://thebanner.com), grounded in that site's real
extracted CSS: navy-charcoal ink `#232b39` on flat white, blue primary `#1458a9`,
the signature orange section kicker `#ff6207` (with an AA-safe `#c2430b` for
text), The Banner's own purple `#520bc4` for links, Mona Sans (an open stand-in
for GT America) with a DM Serif Display accent, 4px radius, hairline rules. It
ships full custom layouts — `BannerBillLayout`, `BannerBillListLayout`,
`BannerHomeLayout` — and loads Mona Sans conditionally from
`application.html.erb` when `theme_id == "banner"`.

## Structural layouts

A theme can restructure a page, not only recolour it. Four registries resolve
the current theme through `useActiveThemeId`:

- `billLayoutFor` — bill detail
- `billListLayoutFor` — `app/frontend/components/bill/list-layouts/`
- `homeLayoutFor` — `app/frontend/components/home/layouts/`
- `legislatorsLayoutFor` — `app/frontend/components/legislators/layouts/`

A theme with no entry falls back to the default card list and hero.

## The logo is brand-fixed

The Sway wordmark (`public/images/sway-us-light.png`, rendered by `SwayLogo`)
appears as-is in every theme. It sits outside the token system — a theme never
recolours or re-skins it. It is a self-contained badge, so it needs no light or
dark variant.

## Removed themes — do not reintroduce

`draft`, `statehouse`, `broadsheet`, `classic`, `chamber`, `sumi` and the old
`legacy` theme were removed entirely: CSS, registry entry, Ruby allowlist and
any custom layouts.
`DEFAULT_THEME_ID` and the TypeScript `ThemeId` fallbacks all resolve to `sway`,
and the default mode stays `light`.

## History

Themes were built over three steps, each gated by user acceptance:

- **Step A** expanded the design tokens past colour — type system, density, rule
  language, texture, motion — and made every shared component token-driven. Page
  structure stayed identical across themes.
- **Step B** gave the bill detail page per-theme structural layout.
- **Step C** extended that to the bill list and home pages.

Each step was seeded by throwaway HTML mockups opened in a browser for review;
they were never production code and are not kept.

The design rule those rounds produced — ground each theme in one real-world
artifact and follow its conventions — is recorded in
[Why every theme is grounded in a real artifact](../../../../lat.md/explanation/theme-tokens.md#why-every-theme-is-grounded-in-a-real-artifact).
