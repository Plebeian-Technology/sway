---
mode: explanation
summary: "Why the Maryland and Baltimore term-cycle anchor years are fixed constants rather than computed from Date.current, and how each is verified against its live roster."
status: agent-extracted
related: []
---

# Why the term-cycle anchors are fixed constants

`SeedPreparers::Legislators::OpenStates::MARYLAND_TERM_ANCHOR_YEAR` and
`SeedPreparers::Legislators::Sway::BALTIMORE_TERM_ANCHOR_YEAR` are stable
election-cycle anchors, not derived from `Date.current.year`.

## Maryland

The Maryland General Assembly is elected in November and SEATED in January
of the following year. The Nov 2022 election seated on Jan 11, 2023, so the
authoritative `current_role.start_date` year for a sitting MD legislator is
2023, NOT the 2022 election year.

Do NOT use `Date.current.year - 2` here — that drifts one year forward every
calendar year, and from 2027 onward it would report a phantom new term for
every one of the ~191 Maryland legislators whose JSON omits `start_date`.

`OpenStates#term_start_year` reads the year of `current_role.start_date`
when present (the authoritative case). Otherwise it falls back to this
STABLE anchor (`MARYLAND_TERM_ANCHOR_YEAR` plus whole 4-year cycles) that
returns the same year for the entire real term window, so no phantom term
rollover can fire even when called in a future calendar year. Verified: all
191 live Maryland entries lack `current_role.start_date`, so this fallback
IS the sole term source for the whole Maryland roster.

## Baltimore

Do NOT use `Date.current.year - 2` here either — that drifts one year
forward every calendar year, and from 2027 onward it would report a phantom
new term for the scraped Mayor/Comptroller, whose JSON omits the term keys.

The Baltimore municipal cycle (Mayor/Comptroller/Council) runs on 4-year
elections: 2024 → 2028 → 2032. Integer floor division returns the SAME
anchor year for every year within a real term window.

`Sway#term_start_year` checks both key spellings (`term_start_year` /
`termStartYear`) — council members carry real `OfficeRecord` years.
Otherwise it falls back to this STABLE Baltimore cycle anchor.
`authoritative_term?` is true only when the blob carried
`term_start_year`/`termStartYear` (for example, council members via a
`BaltimoreRefresh` `OfficeRecord`). It is false for the scraped
Mayor/Comptroller whose JSON omits the term keys — so `#proven_terms` (the
`Base` default) never reports the cycle-anchor fallback as a proven term.
