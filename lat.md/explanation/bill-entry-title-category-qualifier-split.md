---
lat:
  mode: explanation
---

# Why a bill list row shows both halves of the title

Baltimore and Maryland name their bills with dash-separated parts, and the FIRST part is the CATEGORY, not the actual subject of the bill:

```
Rezoning – Inner Harbor Parcel B
Rental Dwellings – Pricing Algorithm Use – Disclosure
Employees' Retirement System – Art Museum Employees – Eligibility
```

If a list only showed that first part, it would be nearly useless to scan: four rows in a row might all say "Rezoning," three might all say "Zoning" — and the part that actually says which bill this is would be missing. This is worse than it sounds, because a bill whose summary hasn't been generated yet has no other text on the row to tell it apart from the others.

## The split

Each list entry shows both parts: the category comes first, and the rest (the "qualifier") follows in a lighter, less prominent style (`BillEntryTitle`, backed by `splitBillTitle`).

## Why the detail page does it differently

The single-bill DETAIL pages instead show the category as a big heading with the qualifier as a subtitle underneath.

The single-bill DETAIL pages instead show the category as a big heading with the qualifier as a subtitle underneath — what journalists call a "deck." That works there because there's only one bill on the page, so the category isn't competing with neighboring rows for attention the way it does in a list.

## What billEntryTitle.test.tsx checks beyond presence

Most of this file's checks ask whether some text is PRESENT, and printing the whole raw title passes all of them, because the raw title contains everything.

So the default layout could sit in this list looking guarded while it showed a reader several hundred characters of legal wording. Two further checks close that gap: one asserts the "FOR the purpose of" clause that reads the same on almost every bill is DROPPED from the rendered text, not merely that the wanted text is present.

The other names the exact expected string, in a block that runs against all five layouts, which is what makes them agree: a layout that renders a title its own way fails here rather than quietly differing from its neighbours. It reads the whole page text on purpose: `getByText` compares against an element's OWN text nodes and skips text inside a child element, and the subject and the part after it are deliberately two elements so each theme can style them apart — so no single element holds the finished title.
