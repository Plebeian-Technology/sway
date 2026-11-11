---
lat:
  mode: explanation
---

# BillCreatorPicker mechanics

Why BillCreatorPicker is a searchable combobox with a pinned sentinel option.

## Why NEW_BILL_VALUE is a shared sentinel string

A stand-in value that means "no existing bill is picked".

On the Creator, Scheduler and Summary tabs that means "make a new bill"; on the Pipeline tab it means "run every bill". BillCreatorShell imports this and checks for it in its onBillChange handler.

## Why localeSelector is a slot, not built here

Slot for the locale switcher, built by the shell (which owns unsaved-changes warnings and page navigation) — keeps this component purely about display.

## Why IPickerOption copies the raw interesting score onto the option

A dropdown option that also carries the bill's raw "interesting" score, copied on here so sort-by-score can read it directly instead of looking the bill up again.

The number itself is never printed — deliberately kept out of the UI; BillPickerRow shows badges derived from it instead.

## Why BillCreatorPicker is a searchable combobox, not a plain dropdown

The single bill selector shown above all four creator tabs — draws the control only.

The shell handles navigation and unsaved-changes warnings via onValueChange; "new bill" becomes "All Bills" on the Pipeline tab.

A plain dropdown becomes unusable once a locale has dozens or hundreds of bills, so this is a searchable combobox — filters by bill number or title, with "new bill" pinned at the top.

## Why sortMode lives only in React state

Sorting starts alphabetical. This lives in React state only — it is not saved to the browser or the URL — so a page reload goes back to A-Z.

## Why keywords carries the full stored title (and what broke without it)

Extra text people can search on, including things the row shows but the short label leaves out (sponsor, status, ...).

The full stored title belongs here too — filterComboboxOptions searches only label + keywords, and shortBillTitle cuts Baltimore titles at "FOR the purpose of," where the subject usually lives.

Omitting it broke search: typing "Hendler" returned no matches on a locale that had the bill. Keywords are searched but never rendered, so the label stays short.

## Why sorting compares the lowercased label

Sorts on the lowercased label — lodash compares raw characters, so capitals sort before lowercase and a mixed-case list would look randomly ordered. Used by both A-Z mode and the score tiebreaker.

## Why score-mode sorts unscored bills to the bottom with an alphabetical tiebreaker

In score mode, no score counts as -1, so unscored bills sink to the bottom; label is the tiebreaker, so ties (every unscored bill at -1, every zero-signal bill at 0) break alphabetically.

Without that tiebreaker, a locale where most bills are unscored would end in a long tail that looks randomly ordered.

## Why the picker caption is a plain span, not a Radix Label

A plain caption, not `<Label htmlFor>` — Radix's Label blocks double-click text selection and opens the control on click. Screen readers still tie it via aria-labelledby; text stays copyable.

## Why the caption row wraps

The caption and the two controls beside it sit in a `flex-wrap` row so they stack on a narrow screen instead of pushing the page sideways.

Without the wrap this row was one of three places in the Bill Creator that made the whole page scroll horizontally at 320 pixels, dragging the tab content with it — found on the first run of the narrow-viewport browser checks. The other two were the tab strip and the form header's buttons. None of the three was new work; they were pre-existing and simply unmeasured until something looked.

## Why SIGNAL_BADGE_ORDER is a fixed order, independent of interesting_badges

The three signal badges always appear in this order: controversial, then close, then live.

Only the signals listed in bill.interesting_badges are drawn; that list's own order is ignored, so a badge never shifts sideways depending on which others are on.

Missing data must look missing, not invented. An empty list — including a bill with no score yet (interesting_score_normalized null) — draws no signal badges at all.

"close" never shows up on a Baltimore city bill: the server never puts it in the list for those.

## Why BillPickerRow shows the fuller row inside the open dropdown

One row inside the open bill-picker dropdown. The closed box still shows the short "external_id — title".

This is the fuller row: sponsor, dates, and how much voting/advocacy activity a bill has drawn — what an operator needs to tell bills apart and spot the interesting ones.

## Why BillPickerSortToggle has no drop shadow

The two-button A-Z / Most Interesting switch above the bill picker. Only draws: BillCreatorPicker holds the chosen sort mode; this passes clicks back up.

Has no drop shadow, so it stays visually second to the picker box below it.

## Why the combobox uses bg-muted instead of the default bg-input

Uses bg-muted instead of the default bg-input — several themes set --input to the same colour as --card, so an unstyled box would blend into this panel and disappear. --muted differs from --card in every theme.
