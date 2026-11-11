---
mode: explanation
summary: "Explains how BillCategoryAssigner turns LLM category names into BillCategory rows: name-based matching across a renamed category, the 3-slot cap enforced under a row lock, and why raising Llm::SchemaError is the one answer no caller picks."
status: agent-extracted
related: [bill-category-assignment-integrity, bill-summary-category-assignment]
---

# How `BillCategoryAssigner` turns LLM names into `BillCategory` rows

`BillCategoryAssigner` turns the category names the LLM returned for a bill
into `BillCategory` rows — the rows that link a bill to its categories,
safely and repeatably. It takes the LLM's raw category names, puts them in
a standard form with `Category.slugify` (the ONE place that normalization
happens — never write it out by hand somewhere else), keeps only the ones
in the active category list the caller handed over, stops at 3, and saves
the link rows with `find_or_create_by!`, so running it again creates no
duplicates.

## How renaming a category works alongside assignment — a settled decision

The in-memory lookup is keyed on `Category.slugify(c.name)`, the CURRENT
name the LLM saw in the prompt, NOT on `c.slug`, the stored slug that never
changes. So a renamed category — slug still `"health"`, name now
`"Healthcare"` — keeps matching an LLM answer of `"Healthcare"`, because
both turn into the same slugified key. The `bill_categories` link row still
points at the stable integer `category_id`.

## When nothing matches: raises `Llm::SchemaError`

Every caller catches it and lets the bill finish with NO categories, which
is the design and not a leftover. `GenerateBillSummaryJob` completes the
row rather than stranding a summary it paid for in a state whose screen
never shows it. `BackfillBillCategoriesJob` stamps
`categories_unmatched_at` so the bill stops asking the model the same
question on every boot. `PasteSummaryService` logs and keeps the pasted
summary.

A new caller has to pick one of those three. Letting this raise travel is
the one answer none of them chose: it marks a good summary failed.

## `#call`: how the 3-category cap works, and why it needs a row lock

Standardize the names, keep only the active ones, take the first 3, save
the link rows.

Add matched categories in order until the bill has 3, and skip any that
would push it past 3. Existing rows are NEVER deleted, including ones an
admin set by hand through `Bills::CategoriesController`. `with_lock` takes
a row lock — on SQLite in WAL mode (its write-ahead log) that means `BEGIN
IMMEDIATE` — so counting and inserting happen as one indivisible step.
Callers running at the same time wait their turn, and the total can never
race past 3.

### Why only active categories count toward the cap

Link rows for a topic an admin later switched off are kept — never
deleted — but must NOT use up slots. A bill holding 3 or more switched-off
rows would otherwise never save an active category, so it would land in
the startup backfill every time and burn one paid LLM call per boot
forever, while the re-categorization meant to fix it could not possibly
succeed. Users only ever see the active categories, so counting only those
keeps the "at most 3 visible" intent while letting re-categorization fill
the slots people actually see.

### Why the return value counts only newly-created rows

Counting only rows this call actually created keeps the return value's
promise of "the categories this call saved" instead of also counting rows
that were already there on a re-run (`bc.previously_new_record?`).

## `#resolve_matches`: why `.uniq` runs before `.first(3)`

The lookup is keyed on the slugified CURRENT name — NOT the stored slug,
which never changes (see the renaming note above).

`.uniq` runs before `.first(3)` so repeated names from the LLM — say
`["Health","Health","Housing","Education"]` — do not eat slots. Without
`.uniq` the second `"Health"` fills one of the three and the valid
`"Education"` is dropped.
