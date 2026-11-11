---
lat:
  mode: explanation
---

# Theme webfonts

Each theme brings its own typefaces, and the `<link>` tag that fetches them is written once by the server into the page `<head>`. Inertia never redraws that head, so switching theme mid-session has to move the tag from the client.

## Why the shared theme prop carries the whole font map

`ApplicationController`'s `theme` shared prop ships all of `ThemeHelper::THEME_FONT_HREFS` — every theme id mapped to its webfont stylesheet href — rather than only the active theme's own href.

Switching themes mid-session is an Inertia partial visit, which swaps the React component and never re-renders the ERB layout that emitted the `<link>` tag. Nothing on the client could regenerate that href on its own from the active theme alone. Shipping the whole map lets `app/frontend/sway_utils/theme_fonts.ts` swap the tag itself while Ruby stays the single source of truth; a hand-kept TypeScript copy of the URLs would be the same drift the theme-id allowlist test already exists to catch.

The failure this prevents is visible rather than subtle: Corner Store without its wood type reads as a plain blocky layout, which is the look the themes exist to escape. The new theme's colours, rules and structure would arrive together while its lettering stayed a whole page load behind.

## Why the layout requests only the active theme's fonts

The layout asks for one theme's fonts, so a visitor on a theme that declares no webfont — such as the default self-hosted `sway` theme — downloads nothing, while opt-in themes such as `service-manual` fetch their typography.

`THEME_FONT_HREFS` reaches the layout through `helper_method :theme_font_stylesheet_href`. A helper method is easy to add and then forget to expose, and the omission raises on every page render rather than merely failing to serve a font, so the exposure carries its own test. Themes sharing identical webfont requirements (`monochrome`, `service-manual`, and `swiss-grid` each pairing Inter with IBM Plex Mono) point to the same multi-family Google Fonts stylesheet href, keeping family definitions unified.

## Why the request specs assert on the link tag, not the body text

A download is caused by the emitted `<link>` tag, not by a URL appearing somewhere in the document.

Because the theme prop carries the whole map, every font URL is present in the response body on every page. Searching the body text can therefore no longer separate "requested" from "merely mentioned", so the specs match the `<link data-theme-fonts ...>` tag itself.

## Why the shared theme prop runs in an instance context

The theme prop lambda runs against the request controller instance.

The `inertia_share` block is declared at class level, but Inertia evaluates its lambda against that request instance. Steep sees the block in singleton context and cannot resolve the included instance helpers, so the narrow `steep:ignore` covers that type-checker mismatch rather than a runtime gap.

## Why theme_fonts.ts reads getAttribute and removes empty links

[[app/frontend/sway_utils/theme_fonts.ts#currentThemeFontHref]] reads `getAttribute("href")` rather than `link.href`, and [[app/frontend/sway_utils/theme_fonts.ts#applyThemeFontHref]] removes the `<link>` element when the target theme has no webfont.

The DOM `link.href` property expands relative paths into full absolute URLs, which would fail equality checks against the server's href string. Removing the `<link>` tag when switching to a theme with no webfont ensures the previous theme's font stylesheet does not remain active.
