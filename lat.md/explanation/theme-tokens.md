---
lat:
  mode: explanation
---

# Theme tokens

A theme re-skins the whole application, not only its colours, so every value a design decision can move — type, density, corner shape, rule weight, texture, motion — is a CSS variable a theme file owns rather than a constant a component holds.

The variables live in `app/frontend/styles/themes/<id>.css`, one file per theme. `tokens.css` imports all of them, and `application.css` maps them into Tailwind's own namespace in an `@theme inline` block, which is what turns `--card` into the `bg-card` utility.

## Why a test enforces the vocabulary

A colour token is declared in three places in each theme file: the base block, the `.dark` block, and the `@media (prefers-color-scheme: dark)` auto block. The auto block is a separate branch, not a fallback the other two flow into.

Adding a token to the base block and forgetting the other two produces no error. The theme keeps rendering, and the missing value silently inherits whatever the light block set, so a dark theme shows a light surface in one component and nobody sees it until a screenshot.

`__tests__/token-contract.test.ts` names every token and the blocks it belongs in, which converts that silence into a failure. `__tests__/contrast.test.ts` then checks the values are legible against the surfaces they land on, and `__tests__/tokenReferences.test.ts` checks no component stylesheet reads a variable no theme declares.

## Why density and motion belong to the theme

Tailwind's `--spacing` is built from the theme's `--space-unit`, so every `p-*`, `m-*` and `gap-*` class in the application re-scales when a theme changes one number.

That is the point of putting density in the theme rather than in a global config: `cornerstore` reads as tight and `sway` as generous without either one editing a component. Motion works the same way through the `--dur-1` / `--dur-2` / `--dur-3` ladder, which is why the themes disagree so widely — `cornerstore` runs 80/140/220ms against `sway`'s 150/200/550ms.

The ladder is reached through the named `duration-fast`, `duration-normal` and `duration-slow` utilities. Each carries a literal fallback matching the default `sway` theme, so a renamed token degrades to predictable timing rather than to the browser's.

Density reaches component sizing by a second route. `--control-height` and `--control-pad-x` are read by `button.tsx` and `input.tsx`, so a control's height and its horizontal padding come from the theme rather than from a hardcoded utility class. Until those two files were wired to read them, the only thing reading either was the theme picker's own `<select>`, which made them tokens the contract required and nothing on screen obeyed.

The two now differ in kind. `--control-pad-x` still expresses a per-theme decision, running from `0.75rem` in `sway` to `1rem` in `cornerstore`. `--control-height` does not: every theme held `2.75rem`, because 44px is a touch-target floor rather than a matter of taste, and a floor is the same number everywhere. A token identical in every theme file is the state [[theme-tokens#Why a token in the contract has to have a consumer|the section below]] describes for `--motion-scale` before it was removed.

The question is settled: `--control-height` left the per-theme contract and collapsed to a single `:root` declaration in `tokens.css`, guarded by a standalone floor test in `token-contract.test.ts` rather than the per-theme block checks. The alternative — letting `cornerstore` and the now-removed `chamber` theme, the two themes that ran tallest before the floor was applied, sit above 2.75rem and keep the token earning its place — was rejected: the pre-floor spread ran `2.375rem` (`sway`) to `2.75rem` (`cornerstore`), which put every theme's prior value at or below the floor, so nothing in that range reflected a theme choosing to run taller. `--control-pad-x` is untouched by this; padding still carries density, and stays a per-theme token running `0.75rem` to `1rem`.

The four icon-only sizes sit outside that token, hardcoded as fixed Tailwind `size-*` utilities rather than reading `--control-height`, so `icon`, `icon-sm` and `icon-lg` needed the floor applied directly at their call site: a base `size-11` (44px) below the `sm` breakpoint, narrowing to the original `size-9`/`size-8`/`size-10` at `sm` and up — the same shape `sm` already uses for `h-11 sm:h-8`. `icon-xs` (`size-6`, 24px) was left out: it appears only on dense admin rows, which clear a separate, lower 24px minimum rather than the 44px floor everything else on this page targets.

## Why the chart label gutter is a theme token

The bill page's district charts set their row labels in uppercase at `--tracking-caps`, which runs from `0em` in `sway` to `0.16em` in `ballot`. The same label is a different width in every theme, so the column holding it cannot be one number.

Both charts previously hardcoded that column as a Tailwind arbitrary value, and the two disagreed: `6.5rem` in the votes chart against `5rem` in the affinity chart, for what a reader sees as the same column. `DistrictLabel` truncates unconditionally, so anything wider than the column became an ellipsis and neighbouring districts stopped being distinguishable.

Both now read `--chart-label-gutter`. The values were measured in a browser with each theme's own display face at 12px and weight 900, which is how the label is actually set: the widest district label a chart can render, `DISTRICT 47`, comes to 71px in `sway`, 84px in `banner`, 86px in `ballot` and 89px in `cornerstore`. Each theme's gutter sits above its own figure with room to spare — `5.5rem`, `6rem`, `6rem` and `6.25rem`.

`chartLabelGutter.test.ts` holds those measurements and fails if a theme's declared gutter drops below the width its own label needs, or if either chart goes back to a rem literal. The measurement is recorded rather than re-taken because it needs a real browser with the webfonts loaded, which the unit suite has neither of.

The affinity chart's label also carries a running total in brackets, which can still be clipped in the narrower themes. Nothing is lost when it is: that same number is printed in full in the row's own value column, and the district identity — the part that cannot be recovered from anywhere else on the row — is what the gutter is sized for.

## Why a token in the contract has to have a consumer

The contract test proves every theme declares a token. It cannot prove anything reads one, and those are different properties.

A token declared six times and read nowhere still costs what a live token costs: it is hand-maintained across six files and three blocks each, it appears in review, and it invites a reader to assume a decision was made about it.

Three of them turned out to be read by [[theme-tokens#Why the mobile app generates its palette from sway.css|the mobile app]] rather than by anything on the web, which made them evidence of platform drift rather than dead weight — the web had three separate conventions for a dimmed affordance icon while mobile had been resolving `mutedIcon` all along. The other three expressed no decision at all: `--motion-scale` held `1` in every theme, and killing motion is handled by a `prefers-reduced-motion` block that ignores it.

This is now enforced rather than audited by hand. `tokenReferences.test.ts` fails when a theme declares a token that nothing reads, treating `var(...)` in any `.css` file (including the `@theme inline` block that turns `--card` into `bg-card`) as one consumer form, a Tailwind arbitrary value such as `h-(--control-height)` in a `.tsx`/`.ts` file as a second, and `mobile/src/theme/tokens.ts`'s generator — `scripts/extract_sway_tokens.mjs`'s `TOKEN_KEYS` list — as a third, since that script reads token names straight out of `sway.css` text rather than through `var()` or an arbitrary value. Missing any of the three reproduces the false-orphan failure this section already describes for the mobile-only tokens above.

The same shape turns up past tokens. `application.css`'s `@utility` declarations and `PARITY_COPY`'s leaf keys (`app/frontend/sway_constants/parityCopy.ts`) share the property: something can be declared, pass every existing check, and still have no reader. `tokenReferences.test.ts` and `parityCopy.test.ts` enforce all three — tokens, utilities, copy — under the same no-consumer rule, once for each declaration site rather than once for the vocabulary as a whole, because each is audited against its own kind of usage (a CSS class name for a utility, a dotted `PARITY_COPY.a.b.c` access for a copy leaf).

The `@utility` check excludes `application.css` itself from the search for a consumer: every utility name already appears once there, in its own `@utility <name> { … }` declaration, and counting that occurrence as a use would make the check pass unconditionally.

The `PARITY_COPY` check excludes `parityCopy.ts` (the declaration) and `parityCopy.test.ts` for the same reason: `parityCopy.test.ts` is a shape check, not a screen — it writes `PARITY_COPY.a.b.c` for most leaves only to assert the nested path exists, and counting that as a reader would hide a key no component or screen actually renders. `mobile/__tests__/parityCopy.spec.ts` needs no such exclusion: it reads through a locally re-typed `COPY` alias rather than `PARITY_COPY.a.b.c` directly, so it never matches the consumer search in the first place.

Landing the copy-leaf check surfaced eleven orphaned `PARITY_COPY` keys on the first run. `bill.content.voteBreakdown` was a divergent duplicate: `BillChartsPanel.tsx` rendered "How the vote breaks down" inline rather than reading the constant that held the same sentence. `memberships.acceptLabel` and `memberships.declineLabel` were the mobile case of the same defect — `MembershipCard.tsx` kept its own local `COPY` object with matching wording rather than importing `PARITY_COPY`, exactly the deferred cleanup `docs/explanation/mobile-org-membership-components-design.md` already named. `memberships.title` was a divergent duplicate too: the memberships page's `<h1>` read "My Organizations" where the constant held "My memberships". The other six were `theme.title`, `theme.lead`, `theme.auto.description`, `theme.light.description`, `theme.dark.description` and `theme.errorMessage` — copy for a theme settings screen that was never built; `ThemePicker.tsx` is a compact `<Select>` with only an `aria-label`, and only its three option labels (`theme.auto.label`, `theme.light.label`, `theme.dark.label`) have a reader. `positions.proposeChange` anticipated a UI for turning an edit to a locked position into a pending change awaiting admin approval; the backend model (`OrganizationBillPositionChange`) exists, but neither web (`PositionCard.tsx` disables Edit outright when a position is locked) nor mobile (`PositionCard.tsx`'s own `no-edit-yet` note) builds that flow. All six theme keys and `positions.proposeChange` were deleted rather than wired up.

## Why the active theme is watched rather than passed down

The hook that reports the current theme reads the `data-theme` attribute on the
root element through React's external-store subscription.

Reading the attribute means the theme has exactly one source of truth, the same
one the stylesheets match on. Subscribing to it means any interface that
changes with the theme — a bill page's whole layout, among others — follows the
theme picker immediately, with no page navigation and nothing to thread through
props.

A page that picks a whole layout this way builds its element at run time rather
than writing the component as markup, because which component it is only
becomes known while running. The home page's layouts take no server data at
all: a home layout is self-contained marketing wrapped around the sign-in
panel, so its type carries no props.

## Why native select chrome is defined once, globally

The themed rules for a native `<select>` live in one global stylesheet rather
than inside each themed bill-list layout's own sheet.

A layout's stylesheet loads only where that layout renders, so the locale
picker was themed on `/bills` and fell back to the default control on
`/legislators`, `/bill_of_the_month` and `/influence` — the same theme, the same
application, two different controls depending on the address. The sort and
search controls inside the list layouts use these same classes, so the picker
beside them cannot drift out of step either: there is one rule rather than a
copy per surface. The rules use theme-level tokens only, because a declaration
made inside a layout stylesheet would be silently dropped when a rule moved out
of that file.

## Why the picker test names every theme's chrome

The picker test maps every registered theme to its expected chrome explicitly rather than asserting a non-empty class list.

A fallback like `?? NEO_SELECT_CLASS` makes a non-empty assertion true for every theme, even when an added theme omitted its intended class. Explicitly recording the expected class for each theme ensures any unstyled theme is an intentional decision rather than an accidental fallback.

## Why the sway theme departs from the legacy reproduction twice

The sway theme reproduces the Bootstrap 5 look the legacy application shipped,
and departs from it in exactly two places, both for accessibility.

Bootstrap's status colours are fills rather than text colours: its green and
amber score 1.85:1 and 1.35:1 against this page, so the FOR count, the success
text and the stamped badges do not reproduce them literally.

The legacy controls stood 38px tall. They are 44px here so a tap target meets
the same floor as every other theme, which is what the admin mobile-web pass
asks for and what platform touch-target guidance says. The height token itself
now lives with the shared tokens rather than in this theme file, because a
value identical in every theme is a floor rather than a matter of taste.

## Why the dead-reference check reads app/frontend/styles too

The two checks in `tokenReferences.test.ts` run in opposite directions — one asks whether every reference has a declaration, the other whether every declaration has a reference — and until this they disagreed about which stylesheets exist.

The orphan check has always read every `.css` file under `app/frontend`. The dead-reference check read only `app/frontend/components`, which left `theme-selects.css` and `application.css` unexamined. Neither is small: `theme-selects.css` carries the native select chrome for every theme, written entirely in theme tokens, and a token renamed out of the contract would have left those rules reading nothing while every select fell back to browser default chrome, with no test going red.

The theme files and `tokens.css` are excluded by name rather than by directory, because they are the declaring side: a token they name is defined there, not consumed there, and the check is about references that resolve to nothing.
Not every orphan the check reports is a defect: the registered-voter work splits "write the copy" from "render the copy" into separate changes on purpose, so a web screen and a mobile screen read one already-agreed wording instead of each inventing its own while the other waits. `address.helper.registeredVoterConfirmation.label` and `.description` land with no reader, `parityCopy.test.ts` reports them as orphans until the web screen and the mobile screen each add a `PARITY_COPY.address.helper.registeredVoterConfirmation.*` read, and that gap is the accepted cost of writing the copy once rather than twice.

## Why some rules are read from the computed style

A check on an applied style reads what the browser computed rather than the class list the element carries.

A class written in a form the compiler does not recognise produces no rule at
all, and the class list goes on looking exactly right — every stamp badge
quietly lost its inner ring that way. Only the computed value can tell a class
that resolved from one that was dropped.

## Why the non-text tokens are measured too

`contrast.test.ts` began as a text gate, so the three tokens that are never text — `--muted-icon`, `--chart-muted` and `--border-strong` — went unmeasured, and all three had drifted below the 3:1 that WCAG 2.2 SC 1.4.11 asks of non-text content.

The drift was invisible for the same reason it was possible. A missing pair produces no failure and no output; the gate simply reports green over a smaller surface than a reader assumes it covers. For example, `sway`'s light `--border-strong` was at 1.97:1 against the page, the now-removed `classic` theme was carrying Tailwind's stock slate-400 as a warm theme's icon colour at 2.25:1, and every theme's neutral chart bar was under 3:1 against the track it is drawn on.

The boundary case is `--border-strong`. A control edge only has to meet 1.4.11 when it is what identifies the control, and `input.tsx` is exactly that case: its `bg-input` fill lands within 1.15:1 of the page in every theme, so the edge is the only thing separating a text field from the paper behind it. Native `<select>` and `<textarea>` controls on admin surfaces follow the same rule (`border-neo border-border-strong bg-input text-foreground`): pairing `border-input` with `bg-background` renders a 1:1 invisible border in every theme where `--input` equals `--card` and `--background`.

`--avatar-border` stays out of the gate. It fails 3:1 in every theme, which is the tell that the bar does not apply — an avatar's ring is decoration, and the exception in 1.4.11 covers it.

## Why components never pair raw Tailwind palette classes with dark:

Tailwind's default `dark:` variant matches `@media (prefers-color-scheme: dark)` rather than Sway's `data-theme-mode` attribute or `.dark` class.

When a user's operating system is in dark mode while Sway is in its default `light` mode (`data-theme="sway" data-theme-mode="light"`), `--card` and `--background` resolve to light surfaces while `dark:text-green-300` or `dark:text-amber-200` activate and paint pastel text on white paper. Conversely, when Sway is set to `dark` mode on a light operating system, `dark:` stays dormant and leaves light-mode palette classes on dark surfaces.

Semantic tokens (`--success`, `--warning`, `--info`, `--destructive`, `--surface-2`, and `Badge variant="stamp"`) switch inside the theme stylesheet's `.dark` and `[data-theme-mode="auto"]` blocks, so they track the active theme mode and preserve `monochrome`'s zero-hue ink palette.

## Why the type ladder has to stay monotonic

The `@theme inline` block in `application.css` maps eight type tokens onto Tailwind's `text-xs` through `text-4xl`, which turns each theme's scale into a promise that `text-3xl` renders larger than `text-2xl`.

Nothing in the token contract enforced the ordering, so two themes had inverted a step. `sway` — the default theme every user lands on — set `--type-stat` to 1.5rem beneath a 2rem `--type-h2`, which made `text-3xl` smaller than `text-2xl` and left the vote counts on a bill card visually subordinate to the card's own title. Every other theme sizes the stat above the h2, so the inversion read as an oversight rather than as `sway`'s reproduction of Bootstrap.

`type-scale.test.ts` walks the eight tokens in utility order, resolving a `clamp()` to its first argument because that is the size the ladder has to hold at on the narrowest viewport. It began as an ordering check and now measures the size of each step as well.

Non-decreasing is not the same property as visibly distinct. The now-removed `chamber` theme's `text-lg` to `text-xl` step was 4.2%, and `text-xl` to `text-2xl` was 8.8%, both below the size difference a reader can perceive — so `text-lg`, `text-xl`, and `text-2xl` rendered as one apparent size on a `chamber` page even though every step in the ladder was technically ordered correctly. A test that only checks ordering cannot catch that, the same way `avatar-border` above shows a contrast pass can be the wrong property to check.

`MIN_STEP_RATIO` in `type-scale.test.ts` is 1.125 — a Major Second (9:8) on the classic modular-scale ratio ladder (Minor Second 1.067, Major Second 1.125, Minor Third 1.2, Major Third 1.25, Perfect Fourth 1.333, ...). Major Second is the smallest ratio on that ladder actually recommended for a working type scale; Minor Second sits below it as "barely noticeable, ultra-subtle" steps meant for cases where near-identical sizes are the goal, which is the opposite of a perceptibility floor. Major Second also matches the character the fix needed: it is the ratio dense, data-heavy scales use (dashboards, admin panels), so it widened the now-removed `chamber` theme's ladder without turning it into a large-type theme.

Clearing 1.125x moved more than the now-removed `chamber` theme. Its `--type-h3` and `--type-h2` widened (1.25rem/1.36rem → 1.36rem/1.55rem) while `--type-lede` stayed put, since lede-to-body already cleared the floor. Two other themes were under it too, despite the change that raised this floor appearing to assume otherwise: `sway`'s `--type-display` sat only 1.111x above `--type-stat` (2.5rem/2.25rem → 2.75rem/2.25rem), and `banner`'s `--type-stat` was literally equal to `--type-h2` at 2.25rem (moved to 2.625rem) — a straight ratio of 1, the same class of defect as the `sway` stat/h2 inversion two paragraphs up, just one step removed from an outright inversion. The now-removed `classic` theme's `--type-h3` was also under the floor against `--type-lede` (1.25rem → 1.3rem). `ballot` and `cornerstore` already cleared 1.125x everywhere and needed no change.

## Why every theme is grounded in a real artifact

A theme is designed by reproducing the conventions of one real-world object, not by composing an effect from parts that look designed.

The first round of theme mockups was rejected for reading as machine-generated. What fixed it was picking an artifact per theme and following its actual conventions: the optical-scan ballot for `ballot`, screen-printed Baltimore protest posters and hand-set wood type for `cornerstore`. That move cut two families of decoration at once — effect-soup (staggered reveals, draw-on rules, flicker, animated meters) and decorative gizmos (glowing studs, rotated stamps) — and left typographic restraint doing the work.

The readability themes follow the same discipline: `monochrome` reproduces the density and contrast of zero-hue black-and-white printing ink on paper; `service-manual` reproduces the structured, content-first clarity of GOV.UK and USWDS civic reference manuals with prominent rules and deep civic blue; `swiss-grid` reproduces the disciplined asymmetrical grid and signal red of mid-century Swiss federal notices.

Fidelity to the artifact beats a modern reading of it. The now-removed `broadsheet` theme was first attempted as a modern broadsheet and was redirected to a genuine 1920s to 1930s period newspaper, because period authenticity grounded in the real object is what distinguishes the themes from each other; a generic composite does not.

## Why the mobile app generates its palette from sway.css

`mobile/src/theme/tokens.ts` is generated by `scripts/extract_sway_tokens.mjs`, which parses colour tokens from the default web theme (`app/frontend/styles/themes/sway.css`).

A React Native app cannot consume CSS variables, so the alternative was a hand-kept second palette — and a hand-kept copy of thirty-five colours across light and dark is a copy that drifts. Generation makes the web theme the single source and the mobile palette a build product.

Only colours cross over. Spacing is deliberately excluded because `rem` units are inert in React Native and evaluate to zero without raising anything, so a spacing token that survived the trip would silently flatten a layout.

Elevation does not cross over either, and is a declared platform divergence. A card's shadow is stronger on the phone than the web's soft CSS shadow, because the phone's pale page ground needs more separation for a card to read as lifted at all. A test looking for that shadow therefore matches on its colour rather than on an exact offset or opacity, since those differ between light and dark; the same colour test, negated, is how a shadowless variant is pinned.

Mobile uses the Sway palette in light, dark, or system appearance, aligning mobile surfaces with the default web theme. An earlier design decision chose Bootstrap-style solid badges and underline tabs. That decision supersedes the original neobrutalist issue criteria. Open Sans Light body text and SemiBold emphasis preserve the shared identity.

Native spacing, radii, and shadows have their own values because CSS units and effects do not map directly to React Native. The stronger light-mode card shadow is an intentional platform difference. The [mobile visual audit](../../mobile/docs/sway-visual-alignment.md) separates implemented styling from outstanding device evidence. Source checks cannot establish native font loading or rendered appearance.

## Why navigation shell and secondary pages use token-driven borders

The web navigation shell and secondary pages render through shared components styled with Tailwind and theme custom properties rather than dedicated per-theme layout files.

Hardcoding `border-2` or `border-l-2` in components like `Drawer`, `LocaleSelect`, `Button`, `Dialog`, `Sheet`, `Legislator`, `Organization`, and `Sms` forces a 2px border width across all themes, ignoring `--neo-border-width: 1px` in `service-manual`, `swiss-grid`, and `ballot`. Replacing those hardcoded border widths with `border-neo` and `border-l-neo` allows each theme to govern its own border thickness via `--neo-border-width`.

Similarly, diagonal hover offsets (`hover:-translate-x-0.5 hover:-translate-y-0.5`) impose an active neobrutalist motion on surfaces that adopt flat, restrained aesthetics in `monochrome`, `service-manual`, and `swiss-grid`. Removing diagonal hover translations aligns navigation and secondary pages with flat, print-inspired readability themes while preserving interactive feedback through standard background and foreground color shifts.

The contract is verified in `tokenReferences.test.ts`, which sweeps the fourteen user-facing component files and fails if any file reintroduces hardcoded 2px borders or diagonal translation utilities.

To prevent class collisions in `tailwind-merge`, `app/frontend/lib/utils.ts` extends `twMerge` with `border-neo` directional width utilities so combining `border-neo` with theme border colors preserves both declarations.
