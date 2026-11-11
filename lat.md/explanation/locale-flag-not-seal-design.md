---
lat:
  mode: explanation
---

# Why SwayLocaleFlag is a flag, never a seal

Sway displays official jurisdiction flags rather than municipal or government seals, treating the image as decorative context.

Official government seals carry legal restrictions and imply official state endorsement, whereas Sway is an independent civic platform. The flag image serves strictly as visual decoration because the jurisdiction name is spelled out alongside the emblem in text.

## Where flag files live

Flag SVG files live in `public/images/flags/<slug>.svg`, resolved by the SwayLocale slug.

The directory itself serves as the source of truth. If no flag file exists for a jurisdiction yet, the component degrades to showing no emblem.

## Why the flag image is hidden with onLoad and onError instead of useEffect

Jurisdictions lacking a flag SVG degrade to showing no image rather than a broken-image icon using native DOM event handlers.

Using inline `onError` and `onLoad` handlers avoids React lifecycle synchronization lag. When an image fails to load, `onError` sets `display: none`. When switching to a jurisdiction whose flag exists, `onLoad` restores `display: ""` so the hidden state does not persist across in-place source changes.

## Why layout props carry a raw slug alongside display text

Components require raw jurisdiction slugs to resolve static assets while displaying formatted labels to readers.

Display text has already passed through formatting helpers, whereas asset paths such as flags require the canonical `swayLocaleSlug` identifier.
