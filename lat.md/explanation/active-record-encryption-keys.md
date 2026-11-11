---
lat:
  mode: explanation
---
# Active Record encryption keys

Encrypting a column ties its contents to three keys that live outside the repository. Sway reads them from the environment rather than from Rails credentials, and that choice has consequences a reader meets first in a worktree and last in a disaster.

## Why the environment rather than credentials

Rails' own home for these keys is `config/credentials.yml.enc`, unlocked by
`config/master.key`. That key file is untracked, so credentials read as absent
in exactly the places contributors and agents spend most of their time.

A second checkout (a git worktree) is given tracked files alone, and a fresh clone is given none
of it. Only the main checkout holds the master key, which makes the Rails
default an asymmetry between environments the same code has to run in.

An environment variable carries no such asymmetry. The same three names are
what a developer machine, a worktree, CI and the production container all
read, and the only thing that differs between them is whether a value happens
to be set. That symmetry is the whole reason for departing from the Rails
default.

The delivery path is the one every other Sway credential already takes, and is
mapped in [[settings-and-secrets#Active Record encryption keys]]. The values
are held in Bitwarden, `.kamal/secrets-common` fetches them at deploy time,
`config/deploy.yml` lists them under `env.secret`, and Kamal pushes them into
the running container. No part of a key is ever stored in git.

## A lost key is a permanent loss

There is no recovery path for a lost encryption key. The key is the only thing
that turns a column's ciphertext back into a phone number, an address or an
email.

A key that nobody has left is a column nobody can read again — not by support
request, not from a Rails console, and not by restoring a database backup,
because the backup holds the same ciphertext and no key.

That is why the values live in a password manager rather than on the machine
that uses them, and why rotation is a migration rather than an edit. Replacing
a key without first re-encrypting under the new one destroys the data as
surely as losing it.

The salt deserves the same care as the two keys. It is not a public parameter
here: both real keys are derived from the primary or deterministic secret
together with the salt, so a changed salt is indistinguishable from a changed
key.

## Absent keys do not stop the application

A missing key is not a boot failure. `config/application.rb` assigns only the
values it actually finds, so an environment with none of the three set still
starts normally.

The failure arrives only when a key is asked for — on the first encrypt or
decrypt of an attribute, or on a direct read of
`ActiveRecord::Encryption.config.primary_key`, which raises
`ActiveRecord::Encryption::Errors::Configuration` naming the missing value.

Deferring the failure is deliberate. Encryption is arriving column by column
across several pieces of work, and a fresh clone with no keys still has to
boot, run its tests and serve every page that touches no encrypted column.

The reads happen once, while the application class is being defined, so a
process that is already running cannot pick up a key that appears in its
environment later. Anything proving the wiring therefore has to start a second
process rather than change a variable in place.

## Test environment keys

RSpec runs from the same worktree an environment variable might never reach,
so the test environment does not source its keys from `EnvSecret` at all.

`config/environments/test.rb` assigns three fixed values directly, in the
`Rails.application.configure` block that runs after `config/application.rb`'s
class body — so the fixed values are what `ActiveRecord::Encryption.config`
ends up holding, overwriting whatever the class body found (nothing, since
the three `ACTIVE_RECORD_ENCRYPTION_*` variables are unset in test).

The values are ordinary strings such as `test-primary-key-not-a-real-secret`,
chosen to be unmistakably fake rather than to resemble generated key
material — the same reasoning behind `ApiKey.hmac_secret_key` and
`PhoneCacheKey.hmac_secret_key` returning the literal `"test"` in this
environment. They protect nothing, so being tracked in git and identical on
every machine and run is a feature rather than a leak.

## Development environment keys

Development carries its own three fixed values for the same reason test does, and they are just as fake.

The gap is not cosmetic. Reading `ActiveRecord::Encryption.config.primary_key`
in development with no key set raises
`ActiveRecord::Encryption::Errors::Configuration` — not writing an encrypted
value, not loading an encrypted row, merely asking whether the key exists.

So the first `encrypts` on any column would stop development outright. Signing
in, registering and seeding all touch the user row, and each would raise on a
machine with no keys, which is every fresh clone.

`config/environments/development.rb` therefore assigns
`development-primary-key-not-a-real-secret` and its two siblings. The
development database holds seeded fake data and the values sit in a tracked
file, so they defend nothing and are not meant to. Production is untouched and
still reads real keys from the environment through `EnvSecret`.

A consequence worth knowing: rotating these would make existing development
rows unreadable, exactly as in production. Re-seeding is the remedy there,
which is why the values are fixed rather than generated per machine.

## The worktree trap

The same tolerance that lets a fresh clone boot makes a second checkout quietly
misleading once columns are encrypted. A worktree carries no `.env` files of
its own and no `config/master.key`.

Encrypted columns there are unreadable unless the keys reach the worktree
through the environment — true for a dev server or a console, but not for
RSpec, which carries its own fixed keys in the tracked test environment file
regardless of what the worktree's environment supplies. The symptom outside
test is a spec or a boot that fails in a worktree and passes on the main
checkout, with a failure that describes a missing key or a value it could not
decrypt and says nothing about the change under test.

A red gate in a worktree is worth re-running on the main checkout before it is
believed, which is the same caution [[verification-gates]] records for the
git-under-Docker failures.
