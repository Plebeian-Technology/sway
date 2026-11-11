---
lat:
  mode: explanation
---

# Theme test suite: five silent-failure guards

`app/frontend/styles/themes/__tests__/` exists because a broken theme is never an error anywhere in the normal toolchain.

A missing or unreadable CSS variable passes lint, type-checking, unit tests and a screenshot — the page still draws, it just draws wrong, and only real content at real sizes makes anyone notice. Each file in this directory guards one specific way that can happen.

## Colour notation: one shared module for two gates that used to disagree

Both the contrast gate (`contrast.test.ts`) and the bundling gate (`css-bundle.test.ts`) need to know what a CSS colour value looks like. They used to carry their own idea of that, independently, and the two disagreed.

The contrast gate reads `#rrggbb` and `rgb()`, because a theme that wrote `rgb(95 207 137)` where its neighbours wrote `#5fcf89` skipped the check entirely over that spelling, and shipped an unreadable mint green. The bundling gate was never taught that lesson: it matched `#rrggbb` only, so the same theme would have looked like it declared no colours at all. It still failed — but it said the theme shared every colour with another theme, which is a different problem with a different fix, and would have sent the reader looking for a palette clash that was not there.

`colourNotation.ts` (`app/frontend/styles/themes/__tests__/colourNotation.ts`) is the fix: the one place that knows every notation a theme file may use, whether it can be converted to a comparable hex triple, and the name to print when it cannot. It is a helper, not a test — vitest's `__tests__/**/*.test.ts` pattern never collects it directly.

### Why NOTATIONS' order matters, and why rgba() is recognised but unmeasurable

Order matters only in that the first match wins, so the more specific hex lengths sit ahead of nothing that could shadow them.

`rgba()` is readable in the sense that the module recognises it, and deliberately not convertible: it carries transparency, so there is no single surface to measure it against. Only `--scrim` uses it, and a scrim sits over anything. `namesAnUnreadableColour` excludes it for the same reason — it is recognised and unmeasurable on purpose, not a gate failure.

### Why uniqueColourValue throws two different errors

A colour a theme declares and no other theme does, returned AS WRITTEN so a caller can search built CSS for it.

Uniqueness is judged on the converted colour, so two themes writing one colour in two notations still count as sharing it.

It throws when there is nothing to return, and the two reasons say different things because they have different fixes. Reporting "shares every colour" for a theme that is merely written in an unreadable notation sends the reader hunting a palette clash that is not there.

## Contrast floor: KNOWN_SHORTFALLS is a debt list, not a setting

`contrast.test.ts` measures WCAG 2.1 contrast for every colour pair that really sits on top of each other on screen.

`contrast.test.ts` measures WCAG 2.1 contrast for every colour pair that really sits on top of each other on screen — text against the surface behind it, filled shapes against their `-foreground` colour — reading the same CSS the browser reads.

`KNOWN_SHORTFALLS` names pairs that shipped below the minimum before the test existed. Entries get DELETED as palettes are fixed; adding one is a deliberate choice to let a real user-facing pair stay hard to read. A new theme should add none, and the suite is empty today: the status colours it started with were cleared by making every theme's tone colours readable as text. The last six entries were all one colour — Sway's brand blue, `#3c6ef7` — which measured 4.41 as the surface behind a button label and 3.80 as badge text on its own 12% wash. It was darkened to `#3260db` (5.48 and 4.63), the smallest change that clears both, picked so the brand shifts as little as it can while still passing. The cornerstore theme follows the Sway palette by design, so it cleared at the same time.

### Why the stamp badge pairs measure a 12% tint, not the flat colour

The stamp badge (`components/ui/badge.tsx`) draws each tone as `bg-<tone>/12 ring-<tone> text-<tone>`: the tone colour is the text, and a 12% wash of that same colour is the surface behind it.

That only works if every theme treats its tone colours as text colours readable on the page — the same thing the `--success on --background` pair already checks. Measuring the blend here is what stops a theme from shipping a tone as a pale fill, which would make the badge text invisible.

### Why muted text is measured against every surface, not just --background

Muted text is checked against `--background` above, but that is not where most of it lives: the surface colours sit behind panels, list rows and cards, and `bg-surface-2 text-muted-foreground` shows up in eleven components.

Measuring only `--background` is how muted text at 4.37 on `--surface-2` survived a whole palette review in both sway and cornerstore, and 4.11/4.16/4.30 in banner. A surface nothing measures is a surface anything can ship on.

### Why the auto mode and (data-intensity) blocks are handled the way they are

`auto` is the prefers-color-scheme block: the palette a reader gets when their operating system is set to dark and they have picked nothing in the app.

It is a complete second dark palette, and it used to go unmeasured. It matches the explicit dark block today — `classic.css` even carries a "Keep in sync if dark vars change" note — but "matches today" only stays true if something checks it. It is now both measured and pinned equal to the dark block: the auto block is a copy of the explicit dark block, and this test is what makes that note hold. Measuring auto in the main pass already catches a drift that hurts readability; this separate equality check catches a drift that does not, which is the kind nobody would notice.

The `[data-intensity]` blocks are left out on purpose: they declare only `--neo-border-width` and `--neo-shadow` and no colours at all, so they cannot change any measured pair. A test proves that instead of assuming it.

### Why the notation scan is guarded even though every theme passes today

The scan used to match ONLY `#rrggbb` and `rgb()`, and everything else slipped past in silence.

The scan used to match ONLY `#rrggbb` and `rgb()`, and everything else slipped past in silence — a theme written in oklch, hsl, color-mix or 3-digit hex would have looked like it declared no colours and passed with zero pairs checked. None of the six themes use those spellings today (373 declarations, all `#rrggbb`, plus 11 `rgba()` scrims), so this guards the door rather than reporting a live problem.

## CSS bundle: a nested @import url() that Tailwind v4 silently dropped

`css-bundle.test.ts` guards against a bug where theme CSS never reached the built bundle at all.

`tokens.css` used to pull in each theme file as `@import url("./themes/...")`. Tailwind v4's CSS build inlines the plain `@import "..."` form but quietly drops the `url()` form for imports nested inside another file — so `classic.css` and `sway.css` never reached the bundle and every theme variable resolved to nothing.

Nothing else caught it: the byte-equivalence, token-contract and allowlist-sync tests all read the CSS files straight off disk and never ran the bundler. This test builds `application.css` through the real Tailwind v4

+ Vite pipeline and checks that every theme's block of variables survives

into the built output.

The bug happens one theme file at a time, so checking only two of the six themes would leave the other four free to fall out of the bundle with the test still green. The theme list is read from disk, so a seventh theme is covered the day it lands, and each theme's proof colour comes from its own file instead of being hard-coded, so it cannot go stale when a palette changes.

### Why proofValueFor doesn't just key on --primary

A colour that appears in this theme's file and in NO other theme file, as written. Seeing it in the built output proves that this particular nested `@import` was inlined rather than dropped.

Not just `--primary`: the cornerstore theme follows the Sway palette by design and the two share `#3260db`, so keying on `--primary` would have let cornerstore fall out of the bundle while sway's value still made the test pass.

The notion of what a colour looks like is shared with the contrast gate. This file used to carry its own, narrower one, so a theme written in a notation it did not read was reported as sharing every colour with its neighbours — a different problem with a different fix.

### Why the test asserts specific var(--<name>) calls, not just that theme variables survive

The `@theme inline` wiring in `application.css` must survive the build, so Tailwind's utility classes read the theme's variables instead of Tailwind's own built-in defaults.

A `var(--<name>)` call only appears in the output when a generated utility uses it; the theme files only declare `--<name>:` and never call `var()`.

## Shared file discovery: __dirname vs process.cwd() drift

`contrast.test.ts`, `css-bundle.test.ts`, `token-contract.test.ts` and `tokenReferences.test.ts` each used to find the themes directory and list its files independently.

All four rest on the same promise — a theme dropped into `themes/` is picked up automatically, so the checks keep covering new themes — and four separate answers to "which files are the themes" is the one thing that promise cannot survive.

They had already drifted apart: `css-bundle` worked from `process.cwd()` while the other three worked from `__dirname`, and those two agree only while vitest is run from the repo root. `themeFiles.ts` (`app/frontend/styles/themes/__tests__/themeFiles.ts`) is the fix — one shared answer to where the theme files are and which ones they are. `css-bundle.test.ts` still uses `process.cwd()` for Vite's own `root` option, which is a different question with a different answer.

## Token references: var(--typo) fails nowhere

`tokenReferences.test.ts` guards a different silent failure: writing `font-size: var(--type-h1)` when no theme declares `--type-h1` is an error nowhere.

The browser throws that declaration away and the element quietly keeps the size it inherited. Four theme layout stylesheets shipped that way before this test existed to catch it.

## Theme-id allowlist: two hand-maintained lists with nothing generating one from the other

`ThemeHelper::VALID_THEME_IDS` (Ruby) and the `ThemeId` union / `THEMES` manifest (TypeScript) are two hand-maintained lists of the same allowed theme ids, with nothing generating one from the other.

`allowlist-sync.test.ts` reads the Ruby helper file and checks the two lists agree, turning "keep these in sync" from a comment into something CI actually checks.

It mirrors the pattern in `classic-byte-equiv.test.ts` (which reads a Ruby source file with `readFileSync`) and `token-contract.test.ts` (which regex-extracts values from it).

### The THEMES manifest itself (app/frontend/styles/themes/index.ts)

`ThemeId` is a hand-kept copy of `ThemeHelper::VALID_THEME_IDS` in `app/helpers/theme_helper.rb`.

The `ThemeId` list here and the Ruby list MUST stay identical — nothing generates one from the other, and nothing reads the themes folder. `allowlist-sync.test.ts` compares the two languages and fails CI when they disagree.

`isValidThemeId` is the one place that answers "is this a real theme id". Other code (`useTheme.ts`) imports it instead of keeping its own copy of the list, which cuts the number of places the list lives from three (Ruby's `VALID_THEME_IDS`, the `ThemeId` type here, and a second TypeScript copy) down to two: Ruby's list and this file. The Ruby copy has to exist because Ruby cannot import from TypeScript.
