---
mode: explanation
summary: "Which characters Testimony::CharacterRepair treats as broken-ligature glyphs, the two-tier corroboration rule that governs them, and the repeatable screen that replaced finding them one at a time by eye."
status: agent-extracted
related: []
---
# Testimony::CharacterRepair's break glyphs

<!-- vale Vale.Spelling = NO -->

`mutool draw -F txt` (`TestimonyTextExtractor`) mangles a handful of ligatures
in Baltimore's hearing-testimony PDFs. The same broken pair — most often the
`ti` ligature — lands in extracted text as different substitute characters on
different extraction runs, and `Testimony::CharacterRepair` has to recognize
each substitute before it can repair the word it broke.

## The glyphs, and how each was found

- **U+FFFD** (`Sway::Utf8::REPLACEMENT`) — the original glyph, written by
  `Sway::Utf8.scrub` itself over bytes it could not decode.
- **`$`** — found by measurement: 363 occurrences across the ten
  stored attachment files at the time, against 6,967 U+FFFD.
- **`?`** and **`\`** — found by the screen described below. `?`
  is the character the roadmap originally named, and a comment on this
  class asserted for months that it never actually occurs. That assertion was
  wrong; it survived because the measurement that replaced it
  looked only at non-ASCII characters.
- **U+019F** (LATIN CAPITAL LETTER O WITH MIDDLE TILDE, `Ɵ`) — reported by an
  operator reading bill 25-0064's public testimony PDF directly (`wriƟng`,
  `BalƟmore`). It does not occur in what `mutool` extracts — see
  the measurement below — and is carried defensively, not because it has been
  observed in Sway's own pipeline.

## Why the fix generalizes instead of special-casing each glyph

`WORD_OR_BREAK_RUN` is built from `BREAK_GLYPHS` plus `[A-Za-z]`, so a glyph
absent from that list is invisible to the repair — a run like `wriƟng` reads
as two clean words (`wri`, `ng`) rather than one damaged one, and no count
(`broken_words` or otherwise) ever reflects the damage. Adding a glyph to
`BREAK_GLYPHS` is the whole fix: `WORD_OR_BREAK_RUN`, `#reparable_indices`,
and `#repair_run`'s fallback gate all read that list rather than naming a
glyph directly.

## The two-tier corroboration rule

Every break glyph resolves through the same rule in `#repair_run`, split into
two tiers by what the glyph itself could mean:

- **U+FFFD tier.** Sway writes U+FFFD itself, over bytes it could not read —
  nothing legitimate is ever behind one. When more than one `CANDIDATE_PAIRS`
  substitution matches the bundle's own vocabulary (or none do), an
  all-U+FFFD run may still guess: `FALLBACK_PAIR` is substituted in and the
  word is counted `resolved_by_fallback`.
- **Conservative tier — every other glyph (`$`, `?`, `\`, U+019F).** All are
  real characters that also appear legitimately in ordinary text: `$` as
  currency, `?` ending a sentence that runs straight into the next with no
  space, `\` in a pasted path, U+019F as a genuine Latin letter in principle.
  A run containing one of these where zero or multiple candidates match the
  vocabulary is left EXACTLY as it arrived, counted `left_unresolved`, never
  guessed. This tier is what makes adding a glyph safe: the cost of a wrong
  guess is a rewritten real word, and the tier removes guessing entirely.
  The gate is
  `reparable.all? { |i| chars[i] == Sway::Utf8::REPLACEMENT }` — a single
  non-U+FFFD break anywhere in the run disqualifies the whole run from the
  fallback guess.

A break glyph resolves `resolved_from_bundle` regardless of tier when exactly
one `CANDIDATE_PAIRS` substitution already appears unbroken elsewhere in the
same text — the tier split only matters when that check is ambiguous.

## Stop finding these one at a time

Three glyphs had been found one at a time, by eye, over months, and each time
the fix was to add that one character. A later measurement asked for the distribution
instead. Two passes were needed, and the first one's mistake is the point of
this section.

**The first pass enumerated every NON-ASCII character between two ASCII
letters.** That is the obvious reading of "find the damaged characters", and
it is wrong: `$` — the glyph already confirmed as damage — is
ASCII (U+0024), so the measurement could not have rediscovered the one known
answer it should have reproduced. **A measurement that cannot find what you
already know is there has not been calibrated.**

**The second pass dropped the ASCII filter** and asked instead: which
characters that are not ASCII letters sit directly between two ASCII letters?
That position is exactly `#reparable_indices`' definition, so the measurement
now matches the code it informs.

### The screen: corroboration rate separates damage from punctuation

Counting occurrences alone cannot tell `$` (damage, 363) from `'` (ordinary,
1,283). So each candidate is put to the same question `#repair_run` asks:
treat it as a break, substitute each `CANDIDATE_PAIRS` entry, and check
whether the result already appears unbroken elsewhere in the same text.

Damage corroborates almost always — in a two-million-character bundle the
correct spelling of a common word is present somewhere. Ordinary punctuation
never does: `don't` yields `dontit`, `donttt`, which match nothing.

Measured over bill 25-0064's freshly extracted testimony (1,995,251
characters), the separation is total — there is no middle group to judge:

| codepoint | runs | corroborated | rate | verdict |
|---|---|---|---|---|
| `\` U+005C | 6 | 6 | 100.0% | **damage** |
| U+FFFD | 11,905 | 11,873 | 99.7% | **damage** |
| `$` U+0024 | 363 | 360 | 99.2% | **damage** |
| `?` U+003F | 60 | 50 | 83.3% | **damage** |
| `@` | 2,488 | 0 | 0.0% | ordinary — email addresses |
| `.` | 3,674 | 0 | 0.0% | ordinary |
| `-` | 2,564 | 0 | 0.0% | ordinary — hyphenation |
| `'` and U+2019 | 1,283 / 313 | 0 | 0.0% | ordinary — contractions |
| newline | 1,702 | 0 | 0.0% | ordinary — a word wrapped mid-line |
| 16 others | ≤116 each | 0 | 0.0% | ordinary |

Every remaining candidate scored exactly zero, over thousands of runs.

### The confirming detail: each glyph is one specific ligature

The corroborated runs were then asked which pair they resolved to. A font
encoding failure should map one broken glyph to one ligature; a coincidence
would scatter across pairs.

| glyph | resolves to |
|---|---|
| `?` | `ti` ×50 — nothing else |
| `\` | `tt` ×6 — nothing else |
| `$` | `tt` ×360 — nothing else |
| U+FFFD | `ti` ×10,173, `tt` ×1,694, `ff` ×6 |

Each of the three specific glyphs maps to exactly one pair. U+FFFD is mixed
because it is not a glyph at all — it is what `Sway::Utf8.scrub` writes over
any byte it could not decode, so it stands in for all of them.

### What changed when `?` and `\` were added

Re-measuring the same bill through `Testimony::CleanAndGroupService`:

| count | before | after |
|---|---|---|
| `broken_words` | 12,268 | 12,334 |
| `resolved_from_bundle` | 12,233 | 12,289 |
| `resolved_by_fallback` | 32 | 32 |
| `left_unresolved` | 3 | 13 |
| `group_count` | 26 | 26 |

The deltas are exactly what the screen predicted: +66 broken words (60 `?`
runs, 6 `\`), +56 repaired, +10 left alone — the ambiguous `?` runs, which
are sentences running into each other with no space, correctly untouched.
`resolved_by_fallback` does not move at all, which is the conservative tier
doing its job: not one of the new breaks was guessed at.

**Grouping did not change.** 26 campaign drafts before and after. The open
question — whether glyph damage was fragmenting one campaign
across several drafts, because `Testimony::ExtractedText` relaxes whitespace
and nothing else — is answered for this bill: it was not. Any fragmentation
seen on this bill has another cause.

**U+019F did not occur at all** — zero in the composed text, and zero in
every raw extraction sidecar checked. The operator read it off the PDF
directly, which is a different extraction path than `mutool`, and in Sway's
own pipeline that same ligature arrives as U+FFFD. It is kept in
`BREAK_GLYPHS` defensively: the change is provably inert where the character
does not occur, since `BREAK_GLYPHS` is the only place `WORD_OR_BREAK_RUN`
and `#reparable_indices` read, and it is conservative-tier if it ever appears.

### Running the screen again

The screen is `rake sway:measure:break_glyphs[<external_id>]`. Run it against
a new bill rather than waiting for someone to spot a fifth glyph by eye. It
emits counts only — never testimony text — and marks which glyphs
`BREAK_GLYPHS` already names, so a new one stands out.

It reports a candidate only from five runs upward. Below that a rate means
nothing, and the concrete case is on this bill: one instance of `naive`
spelled with a diaeresis scores 100%, because substituting `ti` gives
`native`, which the bundle really does contain. A rate needs a denominator
before it is evidence. Six runs is the smallest confirmed glyph (`\`), so
five is the floor that keeps every real finding and drops that one.
