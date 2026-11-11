---
mode: explanation
summary: "Why a legislator missing a photo can go unrepaired forever: the seeder guard and the mirror-on-change hook must both be open, and having a photo is what closes the guard."
status: agent-extracted
related: [docs/reference/seedable-model-shared-example.md]
---

# The legislator photo repair interlock

<!-- vale Vale.Spelling = NO -->

A legislator's photo is copied into Sway's own storage once, from an address
the seed file carries (`photo_url`). When that address has stopped working by
the time the copy runs, the person has no face on the site and nothing says
so — the card quietly falls back to a default picture.

Repairing one is a two-step chain, and **both** steps have to be open or the
repair silently does nothing:

1. The seeder writes the new address onto the row. It refuses when the row
   looks hand-edited: `Seedable#seed_or_skip?`
   (`db/seeds/seedable.rb`) compares `updated_at` against `last_seeded_at`
   and skips on a mismatch.
2. The copy runs, and `MirrorsExternalAsset` (`app/models/concerns/mirrors_external_asset.rb`)
   only starts it when the address column **actually changed** —
   `after_commit(if: :"saved_change_to_#{url_column}?")`.

So a row the guard refuses can never have its photo repaired by a deploy, no
matter how good the address in the seed file is.

## Why the correlation holds today, and why it is luck

Attaching a photo moves `updated_at` past `last_seeded_at`, so **having a
photo is exactly what trips the guard**. In practice every
guard-refused row already has a photo, and every row missing a photo is
writable. The correlation is perfect, but it is luck rather than design — any other write
to a legislator row (a name correction, a party change) trips the same
guard and would leave a missing photo unrepairable too. Nothing in the two
classes above guarantees the correlation continues to hold.
