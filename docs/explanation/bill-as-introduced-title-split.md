---
mode: explanation
summary: "Why the stored bill title's legislative 'FOR the purpose of...' clause moved out of the page heading into a separate As-introduced section."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why `BillAsIntroduced` exists

A bill's stored title often runs to hundreds of characters, because after
the subject it repeats the legislature's own "FOR the purpose of ..."
wording. On production, 189 of 218 bills carry that clause; those titles
average 505 characters, and the longest is 4,710.

That wording is real content and belongs on a page about one bill, so
`BillAsIntroduced` keeps it word for word. What it must not be is the page
heading — three themes were doing exactly that, putting a
heading of several hundred characters at the largest type size on the page,
pushing everything a reader came for below the fold.

## The split

## Why the offline system spec's bill fixture avoids a dash in its title

`spec/system/offline_spec.rb`'s examples look for the bill title on the
page to know the page arrived, so the title must reach the screen
unchanged. The bill page splits a title on its dash and rejoins the parts
with an em dash, so a factory default like "Colour - 20260805…" would
leave the stored text and the shown text differing by one character. The
fixture's title has no dash, keeping these examples about offline caching
— their actual subject — rather than about this unrelated rendering
transform.

The heading carries the subject; the stored title moves down into
`BillAsIntroduced`, under a label that says what it is. The component
renders nothing for the 29 bills whose title has no such clause, since the
heading already shows the whole thing there and a block repeating it would
only add noise. The ballot and corner-store layouts already handle this
split in their own markup, so they do not use this component.

## shortBillTitle must keep the clause searchable even though it drops it from the label

`shortBillTitle` cuts titles at "FOR the purpose of" (189/218 production bills carry it);
dropping the clause from the label without keeping it in keywords lost search.

`BillCreatorPicker.test.tsx`'s subject-matter search tests exercise this against a real
production title — every fixture elsewhere in that file is "Alpha Bill"-shaped, with no
clause and nothing after one, so no other example could see this defect.

## Why `billLayoutRender.test.tsx` renders every theme's layout

A theme's layout loads on demand through `React.lazy` and renders inside
`<Suspense>`. So a layout that THROWS while rendering — a bad import, or
reading an optional bill field without checking it first — leaves a blank
space and no error anyone would notice. `billLayoutFor.test.ts` proves each
theme resolves to a different component; this file proves each one really
mounts and shows the bill.

The fixture bill's title carries the "FOR the purpose of" clause on
purpose: it was written with the clause in it and the comment said the
layouts push it out of the headline — but nothing checked, and three of the
six were setting the whole thing as the page heading.

Dropping it from the heading must not lose it. A bill's own page is exactly
where the full wording belongs, as long as it is labelled.

## `billTitle.ts` helpers

The "FOR the purpose of" clause is Maryland legislative boilerplate; the
plain-language summary carries the real content, so the headline drops it.

`hasLegalClause` tells a page whether its heading is showing the whole
stored title or only the front of it. On production, 189 of 218 bills
carry the clause.

`shortBillTitle` produces exactly the text `BillEntryTitle` renders, so a
picker and a list never disagree about a bill's name — it exists for the
places that need a plain string rather than markup: an option label, a
dialog heading, a chart label read out to somebody using a screen reader.
