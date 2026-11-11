---
lat:
  mode: explanation
---
# Rehearsing a deploy before it happens

Two scripts run the production image on purpose: one rehearses the deploy's own commands against a copy of the real database, the other measures what a boot in that image costs.

## What a rehearsal answers that a spec harness cannot

The snapshot harness swaps the database connection inside one long-lived test process and calls the migration runners by hand, which answers whether the migrations apply to this data.

The question the rehearsal exists for is about process boundaries: whether the
rake tasks the entrypoint runs can share one Rails process, or whether the
schema one of them changes goes unnoticed by the models another has already
loaded. A harness that never starts a second process cannot see that.

The platform is the other half. The harness runs on a different distribution
against a SQLite built by the development image; production is a different
architecture on a different C library with its own compile options. Running the
real production image approximates none of it.

Each command form runs as real processes against its own throwaway copy, and the
schema, the migration ledger and every table's row count are recorded and
compared. A difference is the stale-schema hazard showing itself.

The pristine snapshot is never opened, not even read-only: opening a SQLite file
in write-ahead mode can rewrite it through recovery or checkpointing, so
everything works on copies.

## Why the frontend's own note is checked before the image ships

The build leaves a small file recording which directory the frontend sources came from, and Rails reads it to turn an entry point's name into the name of the built file to send.

Lose that file and nothing complains at build time. Rails falls back to the
directory a Rails project normally uses, looks for a file that was never built
under that name, and raises — on every page, for every visitor, the moment the
deploy lands. A dockerfile that stops copying the public directory, or an ignore
rule that grows one line, is all it takes.

The check therefore asks the image the same question Rails will ask it, reading
the note and building the name exactly as the Rails helper does, for both entry
points because the site has two and only one is on most pages. It runs before
the database rehearsal because it takes a second where that takes minutes, and
it overrides the image's entry point, which would otherwise start Rails and
demand deploy values this check has no business needing.

## Why a practice run cannot land on the machine serving the public

Which machine a target name resolves to is asked of the deploy tool rather than worked out separately, because the deploy tool is what decides in the end.

The practice settings can come to name the machine that serves the public, for
example after the application moves onto the former practice machine. Deploying
to the practice target would then start a second application there sharing the
same storage directory — and a container runs migrations, sets up its job
database and seeds while it starts. Two programs writing one SQLite file is how
that file is lost, so the rehearsal resolves its target itself and refuses one
that is the serving host.

## What a runtime measurement is worth

A one-line change whose entire value is a number is not worth acting on unproved, and "it felt faster after the deploy" is not a measurement.

The measurement runs on the machine the answer is about; a fast development
machine will happily report that everything is fine. It measures one full
production boot per iteration — eager loading, every initializer, the whole gem
set — because that is what the container pays before it can answer a health
check, and each of the entrypoint's boots costs it. Peak resident memory is read
by the booted process about itself, so no external profiler is needed, and the
median of several runs is reported because a mean lets one descheduled run move
the answer.

The first version of that script produced nonsense, which is the reason the
current one is shaped as it is. It installed the allocator under test inside the
timed region and inside a container with no network, so the install failed
silently, the preload pointed at a file that was never there, and the rows for
the variant under test were six times slower than the baseline — timing failed
network retries. The allocator now goes into a derived image at build time and
both runs use that same image. The clue was that a second variable the script
also printed read identically in every row, which is what says the variable
under test is not the variable doing the work: the just-in-time compiler is
already on by default and needs no setting.
