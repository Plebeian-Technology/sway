---
lat:
  mode: explanation
---

# SeedLegislatorTerms: three moves, in order

`SeedLegislatorTerms` writes one legislator's `LegislatorTerm` rows from what the source proves.

It was split out of `SeedLegislator` because it is a different job: `SeedLegislator` settles who the PERSON is, this class settles which SEATS they held and when. It also does more than add rows, and mixing "never touch an existing row" with "correct this one" inside a single method made the rule impossible to read.

## The three moves

The legislative roster updater transitions legislator records through three distinct actions: adding, correcting, and retiring terms.

1. **ADD** — always. Every term the source proves, plus a current term for
   a member the source still lists. That last one is what makes a brand
   new member scoreable before any history has been published about them.
2. **CORRECT** — only against a complete history. A stored term whose
   start year matches a proven term takes that term's end year and title.
3. **RETIRE** — only against a complete history. A stored term whose start
   year appears in NO proven term is deleted, with its score rows.

## Why CORRECT and RETIRE are guarded

congress.gov reports one entry per Congress, so a senator's six-year term arrives as three two-year pieces.

Correcting against that list would cut every senate term back to two years and put sitting senators out of office. Only a source that publishes whole terms with real end dates may drive these two moves, and the preparer says so through `#terms_from_history?`.

`#terms_from_history?` is true only when `#proven_terms` is this person's COMPLETE history — every term they ever served, from a source that records the year each one ended. The seeder is allowed to correct a stored term, and to delete one that appears nowhere in the list, but only when this is true. Against a partial list either move would destroy a real row. It is false by default: a source has to say so.

Two separate things have to hold, and a subclass answering this must check both. The LOCALE has to declare that its roster source publishes whole past terms at all (`SwayLocale#term_rules`), and the ENTRY in hand has to actually carry that history. A subclass written for one locale can be reused for another whose source publishes less, so the locale gate is what stops a new locale inheriting permission to delete terms.

## Why RETIRE exists at all

People who had left Congress can still read as in office because an earlier backfill wrote them a term running to 2027 that no election ever started.

Nothing upstream can correct a term that never began — the row itself is the error, so it has to go.

## Why the default proven_terms is per-locale

`Base#proven_terms`'s default is the single current term when `authoritative_term?` is true, and empty otherwise — correct for locales whose source blobs carry no per-term history (Maryland/Baltimore).

`CongressDotGov` overrides this to walk EVERY `terms.item` entry, not just the current one — the committed Congress JSON carries real prior-term history (for example, a member who moved from the House to the Senate), so every entry with a `startYear` is proven, never fabricated. An entry missing `startYear` is dropped; it proves nothing.

## Nothing here invents a term

Every year written comes from the source. A person the history source cannot answer for keeps exactly the rows they had.

## Why ADD skips the current term for a departed member

`add_missing_terms!` makes sure a row exists for every term the source proves, PLUS the current term when the source still lists this person as holding office.

The current term is skipped for somebody the source no longer lists: `#term_start_year` falls back to the running election cycle when a blob proves nothing, so keeping the current term for a departed member would hand them a fresh term running to next year — the exact row this class exists to remove. `Base#current_member?` is the flag preparers must answer for this; writing that term for somebody the source no longer lists would invent the row the departed-member fix exists to remove.

## Why CORRECT never touches the seat

`create_term!` writes the seat a term names.

A term keeps the seat it names. Only Congress data says which seat each term was served in; every other source says nothing, and those terms take the seat the person holds now. Writing the current seat onto every term was wrong for anyone who has changed district: a member who moved from Florida's 13th to its 16th would have both terms recorded as the 16th.

Later, `correct_terms!` deliberately leaves the seat alone too: moving a term to another district moves every vote counted under it, which is a bigger change than the issue that introduced `correct_terms!` asked for and needs its own measurement. It writes only when something differs, so a second run changes nothing.

`SeedPreparers::Legislators::Base#district_for` takes the state and the number instead of reading them off the top of the blob, for the same reason: a person can hold different seats over time. A representative who moves district keeps ONE `Legislator` row, and each of their terms names the seat they held then. Writing today's seat onto an old term would record something that never happened. It returns nil when the caller has no state to work from, so a term that says nothing about where it was served falls back to the person's current seat instead of failing.

## The termsSource mark and its shape check (congress.gov)

`CongressDotGov#terms_from_history?` reads the `termsSource` key.

`LegislatorsCache::BaseRefresh` writes this key onto every Congress entry whose terms it replaced with the full history. congress.gov's own terms never carry it, so an entry the history source could not answer for is correctly read as a partial list. The President row carries its own curated value instead ([[official-service-evidence#The curated President record]]), and the refresh copies that row unchanged.

The shape is checked as well as the mark. The seeder deletes stored terms this list does not name, and one stray key in a hand-edited roster would be the whole defence against cutting a senator's six-year term down to two. Every term the history source writes carries an end year; congress.gov's own current term never does. Verified against the committed roster: all 546 entries carry the mark and pass, the curated President entry among them.

## The locale gate on published dates

`published_ended_on` and `published_began_on` are gated on the LOCALE declaring that its source can give an exact day (`SwayLocale::TermRules#publishes_exact_term_dates`), not on the preparer class.

A preparer written for one jurisdiction can be reused for another whose source publishes less, and the locale gate is what stops a locale added later inheriting permission to write a date nobody published.

An end date on the seat a still-listed member sits in is a schedule, not a departure, even once its day has passed. Two appointed senators carry their special-election day; only the roster dropping a person proves they left. `correct_terms!` clears a stored one by the same rule, so removing either half alone changes nothing — they are a pair. A future day on a past term or a departed entry is malformed data and is dropped too. A future begin day IS kept, though: somebody not yet seated reading as not yet serving is the honest answer, and the day arriving makes it true.

## What production_departed_members_spec.rb verifies

`spec/production_readiness/production_departed_members_spec.rb` seeds the committed roster onto a copy of real production data and checks the outcome, rather than trusting a line in a deploy log.

People who had left Congress still read as in office, because the roster carries only current members and the seeder could only ever ADD a term (see "Why RETIRE exists at all" above). The fix puts those people back into the roster with the terms the published history proves, and lets the seeder correct and retire rows against that history.

After the seed, fewer people read as in office, fewer Congress terms are stored, and no vote lacks a covering term. Some departed people stay, and "keeps a departed person in office only while their proven term still runs" says why: they left during 2026, and Sway hands a seat over in January only. That is the widening limit described above, not a row this fix failed to correct. That example is stated as a rule rather than as a number: anybody who has left and still reads as in office must have a proven term that runs past today — which happens only because a term is recorded as two YEARS and a seat can only change hands in January. If somebody shows up there whose history ended before today, that is a real failure to correct their row.

### The blast radius check

Correcting and retiring are gated on the history mark (`termsSource`), not on having left, so they run for EVERYONE the history source answers for.

On a real snapshot the seed deletes, rewrites and adds term rows for many more people than the ones who left. Most are sitting members holding rows an earlier backfill invented, such as a second term that never started.

Every other example in the spec looks only at the people who left, so all of them would pass while the seed quietly deleted a real term from somebody still serving. "leaves every history-backed person holding exactly the terms their history proves" closes that hole by checking every marked entry, not just the departed ones.

### Multi-locale snapshot reconciliation

The production snapshot rehearsal verifies that running `SeedSwayLocale.run` followed by `SeedLegislator.run` across Baltimore, Congress, and Maryland restores full data integrity without manual intervention.

Every declared `LegislativeSession` across Baltimore, Congress, and Maryland is synchronized into the database under default `force: false` even when `updated_at != last_seeded_at` triggers the scalar skip guard, enabling `Bill.current_session` to resolve active bills.

The migration-synthesized POTUS term in US0 is retired during executive term processing, leaving zero terms in US0 while preserving the person and bioguide identifier.

Every currently serving term in Baltimore, Congress, and the 191 current Maryland roster members links to a persisted `Seat` in the same district and locale.

Reconciling production users in Congress resolves distinct seats for both Maryland senators alongside district representatives, reactivating co-serving members and populating term scores.

## Why a published end date replaces an observed one

A term already stored gains its real end date the first time the history carries one — that is what turns people who left during the year from "in office until 3 January 2027" into out of office.

A published date replaces one Sway merely observed, because the jurisdiction's own record beats Sway noticing an absence. Conversely, a stored end that says departed while the roster says serving gets cleared: that stops a passed election-day schedule, or an end upstream moved later, from holding a sitting member out of office. A successor seated mid-cycle gains their real start the same way — without it they read as seated from the January handover, and a two-candidate Senate seat matches nobody's votes.

Upstream records the exact departure day, yet before this fix everyone who left during the year read as serving until the next January handover, and a seat could show two people holding it at once.
