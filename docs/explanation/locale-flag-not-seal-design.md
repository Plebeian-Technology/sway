---
mode: explanation
summary: "Why LocaleFlag always renders a flag rather than an official seal, and why the image is decoration only rather than the sole label for a jurisdiction."
status: agent-extracted
related: []
---

# Why LocaleFlag is a flag, never a seal

Two rules are deliberate choices, not accidents of how this was built.
The image is always a FLAG, never an official seal: seals are legally
restricted, and one would suggest the government endorses this independent
platform. And the image is decoration only, because the name of the city or
state is always spelled out in text right beside it.

## Where flag files live

Flag files are looked up by locale name, per the README convention for
adding a locale (`public/images/flags/<name>.svg`) — the directory
itself is the source of truth; no flag yet just shows none.

## Why the flag image is hidden with `onLoad`/`onError` instead of a `useEffect`

A locale added without a flag image degrades to showing no emblem at
all, instead of a broken-image icon. This is handled with event handlers
rather than a `useEffect`.

`onLoad` undoes `onError` when switching locales in place: without it,
hiding the image for one flagless locale would stay hidden for every
locale picked after it.

## Why `BillListLayoutProps` carries a raw `localeSlug` alongside `localeName`

`localeName` is already formatted for display ("Baltimore, Maryland, United
States"). `localeSlug` is the raw `SwayLocale#name` value
("baltimore-maryland-united_states") — different from `localeName`, which
the page has already converted into a human-readable label via
`toFormattedLocaleName`. Anything that needs to identify the locale itself,
rather than just show its label — like the flag emblem above —
needs this raw value instead.
