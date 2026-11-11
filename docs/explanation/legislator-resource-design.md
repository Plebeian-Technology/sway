---
mode: explanation
summary: "Why LegislatorResource includes contact details, keeps photo_url's key name stable across a mirrored asset, and reads title/district/dates through one shared display_term; and why LegislatorTermResource sends its dates as dates."
status: agent-extracted
related: [mirrored-asset-query-cost-coverage]
---

<!-- vale Vale.Spelling = NO -->

# Why `LegislatorResource` is shaped the way it is

## Why contact details are included

Contact details are included on purpose — reaching a legislator is the
whole point.

## Why `photo_url` keeps its key name across a mirrored asset

`photo_url` returns our own copy of the portrait when Sway holds one, and
the original address when it does not (via `MirroredAssetUrl`, see
[mirrored-asset-query-cost-coverage](mirrored-asset-query-cost-coverage.md)
for the N+1 trap that mirroring avoids). The key keeps its name, so no
screen and no phone app changes. Only the address behind it does.

## Why title, active, and district read through `display_term`

Title, active, and district read from the term being shown
(`#display_term`), not from columns on the legislator row, so a former
rep's fields fall back to their last term instead of coming back empty.

`term_start_year` reads through `#display_term`, not the old (now-gone)
legislator columns of the same name, so the toggle's year-range text
always matches the shown term.

The frontend copy (`PARITY_COPY.legislators`, the "Term toggle +
History" group) has no fixed wording for that year-range text itself: for
a legislator who has left office, the first tab is labelled with the real
years of their term (for example "2019–2021"). That label is built while
the page renders, from `term_start_year` and `term_end_year` above.

`began_on`/`ended_on` carry the real days behind those years, where Sway
holds them, so a member who served part of a cycle stops reading as having
held all of it. They read through the same
`#display_term` as everything else here.

`display_term` itself is the one term every field above reads from, so
title and district can never describe different terms. It falls back to
the most recent held term when the legislator has none active.

## Why `LegislatorTermResource` sends `began_on`/`ended_on` as dates

`LegislatorTermResource` carries the real days, where Sway holds them. A
term is stored as two YEARS, so the years alone say somebody held the whole
cycle — which reads as wrong for anyone who arrived or left partway through.

Sent as dates, not as words: the reader formats them, and mobile formats
them its own way.
