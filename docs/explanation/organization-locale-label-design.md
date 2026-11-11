---
mode: explanation
summary: "Why localeLabelFor exists, what its locales and fallbackSlug parameters mean, and why the fallback path was needed."
status: agent-extracted
related: []
---

# Why localeLabelFor takes a fallback slug

`localeLabelFor` turns a `sway_locale_id` into the short label shown on
screen (city, region — no country). The Organization and Organizations pages
both looked the locale up by id and formatted it without the country, so they
now share this.

`locales` is the jurisdictions the VIEWER belongs to
(`locales_for_current_user`). That is not the same set as the records being
labelled: the public organization directory lists every organization and is
deliberately not limited to the viewer's jurisdictions.

`fallbackSlug` is the record's OWN jurisdiction, in the form the record
carries it (`Organization#to_public_json` fills `sway_locale_slug` from the
locale's city). Without it, a signed-in Baltimore reader looking at a
Congress organization matched nothing, and the jurisdiction line disappeared
from both the card and the detail page. Testing never saw it because a
signed-out visitor's `locales` list holds every locale. The slug is only one
part of the full locale name, so the label it produces is shorter than the
one from the lookup ("Congress" rather than "U.S. Congress") — that is
everything the record itself knows.

## Why `organizationLocaleLabelWiring.test.tsx` checks the call sites, not just the helper

The C2-IN-06 fix added a third argument — the organization's OWN slug — at
two call sites, because `sway_locales` is the VIEWER's jurisdiction list
while both of these surfaces render `Organization.all`. Without it a
signed-in Baltimore user browsing the directory silently loses the
jurisdiction line on every out-of-locale org. It is invisible in most manual
testing, because a signed-out visitor's `locales_for_current_user` is
`SwayLocale.all`, so every org matches.

That fix's RED was written against the helper and never against the WIRING,
so reverting either page to the 2-argument call left the whole vitest suite
and `tsc --noEmit` green — the third parameter is optional, so the type
system says nothing either.

This file is deliberately TWO different kinds of check, because the defect
needs both:

1. A behaviour test of the helper. Cheap, and it states what the slug is
   for. It is NOT sufficient — it is what the original fix shipped, and it
   is the half that stayed green while both call sites were broken.
2. A SOURCE check of the two call sites (`app/frontend/pages/Organization.tsx`
   and `app/frontend/pages/Organizations.tsx`). Neither page can be rendered
   here (each pulls a full Inertia page context), and the argument's
   presence is not observable through the type system, so the only thing
   that fails when a page drops it is reading the page. Same technique as
   `testIdUniqueness.test.ts`. It is a lint, not a behaviour test, and it is
   named that way so nobody mistakes it for one.
