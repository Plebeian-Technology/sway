---
lat:
  mode: explanation
---
# What the development containers are given

The development stack runs entirely in containers, and three of its settings exist because a container does not see the checkout the way a process on the host does.

## Why the geojson directory is mounted through the storage volume

The storage directory is a named volume so that SQLite files stay off the host bind mount, and one directory inside it is bind-mounted back in from the checkout.

Locking on the host mount is unreliable enough to corrupt a database under
concurrent writers, which is why the volume exists at all. The district boundary
files are different: they are tracked reference data rather than something the
application writes, and without them the container reads no such file, so
district matching for the city returns nothing at all while looking healthy. The
submount exposes only that one directory; the volume still owns the database
files beside it.

## Why provision drops the databases through Rails

[[scripts/dip/provision.sh]] drops the development, test and preview databases with `bin/rails db:drop` inside a container, because the files it resets live in the storage volume rather than on the host.

A delete run from the host script reaches only stale copies left from before the volume existed. Provision would then keep whatever the volume held, and `db:seed` would run against it, so a database holding one malformed row fails at seed time in a way a first-time clone never does. Dropping through Rails resolves each file from `config/database.yml` the way the application does, honours the per-environment name overrides, and removes the `-wal` and `-shm` files with it. The development drop covers the test database too, because Rails includes test alongside development. The volume itself stays, since it also holds the Active Storage files under `storage/assets`.

The preview commands run Rails in the production environment, which refuses to boot without the passkey settings, so they carry the same values as the preview service in [[.dockerdev/compose.yml]]. Each command keeps its whole environment on one line: split across two, `bash -c` reads the first line as bare shell assignments and runs Rails in the development environment.

## Why an opt-in flag has to be declared to reach the container

The container tooling forwards a variable into a container only when the compose file names it, so a flag set in the host shell reaches nothing unless it is declared.

Declaring it lets compose read the value from its own environment, which is what
the wrapper sets from the shell that invoked it. Without the declaration the two
opt-in test flags were dropped in silence and the specs they guard never ran —
the failure mode of an opt-in is that nothing happens either way, so it looks
identical to a run where the flag was simply not set.

What each declaration is given is a bare empty string rather than a shell-style
default, because the wrapper's own interpolation understands plain `${VAR}` and
nothing more: an unresolved `${VAR:-}` arrives at compose as that literal text
instead of as an empty value. Empty is also the right answer for an unset flag,
since a value the host did set already wins, and an empty string is not the
value the guard compares against, so the specs stay opted out.

## Why the development image proves the browser can start

The image build launches the browser it just installed, headless, and fails if it cannot.

The browser packages are deliberately left unpinned so a rebuild picks up the
next fix, which means a bad point release reaches the image. One did, and it
crashed on launch — which would otherwise have broken every browser spec at test
time, far from the change that caused it. The smoke test is the guard; a pin
would only trade one silent failure for another.

## What the container declares about the pipeline's tools

Three of the environment values exist because the tools underneath fail quietly rather than loudly or saturate container CPUs when they are missing.

The OCR data path is the clearest: the extractor calls the document converter's
OCR mode, and with the data directory unset that mode emits empty output rather
than an error, so a bill's text simply comes back blank. The value is baked into
the image and repeated here because a compose override can otherwise drop it.
The absence of a message broker is the same kind of statement in reverse:
development matches production in running none, so nothing here names one.

### Why OCR is capped to a single OpenMP thread

The development and production container definitions declare `OMP_THREAD_LIMIT=1` so that Tesseract OCR restricts parallel OpenMP threads during text extraction.

By default, OpenMP detects host core counts and spawns parallel threads across all available cores. Within a container allocated a limited CPU share, unconstrained thread creation produces severe scheduler thrashing and CPU contention. Capping thread execution directly in the image environment guarantees consistent single-threaded OCR processing regardless of container orchestration or host core counts.

## Why the development image excludes its build context and installs Bundler outside the gem volume

The development image copies nothing from the checkout during its build and places Bundler in the system gem directory rather than the default bundle path.

Because application files arrive through a host bind mount at runtime, `.dockerdev/.dockerignore` excludes the entire build context with `*` so edits to `.dockerdev/` files or local runtime volumes never transfer to the builder. Similarly, compose mounts a named volume over `/usr/local/bundle` at runtime, which shadows anything written there during the image build; placing Bundler into `/usr/local/lib/ruby/gems/4.0.0` with its executable in `/usr/local/bin` keeps it visible after the volume mounts.
