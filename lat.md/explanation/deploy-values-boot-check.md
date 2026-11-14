---
lat:
  mode: explanation
---

# Deploy values boot check

Production refuses to start when it does not know a value describing where this copy of Sway lives. `config/initializers/deploy_values.rb` asks for the whole set at once, so a missing one stops a deploy somebody is watching.

Most configuration fails loudly the moment it is first wanted, which is soon
enough. This check exists for the values that do not: the ones read by a
scheduled job, hours later, in a log nobody is reading.

## Why a missing bucket name has to stop the deploy

A bucket name is read on first use, and first use is a backup running unattended.

`DatabaseBackupService` names the bucket the database copies go to.
`Litestream::ReplicaPosition` joins `SWAY_LITESTREAM_PATH` into the path the
continuous copy writes to and lists it every fifteen minutes to confirm the copy
is still moving. Neither can tell a missing value apart from a wrong one — both
list nothing — so without this check the first report of either arrives as a
watchdog that has never once seen a copy to watch.

The legislation artifact bucket joined the set for the same reason.
Its backup walks about twelve thousand files on a schedule and
uploads what the bucket does not already hold, so a missing name would surface
as a sweep that quietly copies nothing, which is the shape
[[legislation-artifact-backup]] is built to avoid everywhere else.

## What the check cannot do

It catches a value that is absent. It cannot catch one that is present and wrong.

A wrong bucket name is the worse outcome of the two, because every upload
succeeds into a bucket nobody reads and the loss appears only during a restore.
No check at boot can distinguish that from a correct name, which is why the
restore itself is exercised rather than assumed.

## Why the check is production-only

The other two environments would each be made worse by it, for opposite reasons.

Test reads the tracked fake values in `deploy/config/sway.test.env`, so it can
never be missing one and the check would assert something already guaranteed.
Development is where somebody is setting Sway up for the first time, and
refusing to boot until every cloud value exists would block work that never
touches them.

## Keeping one installation's values out of the tracked repository

`spec/lib/own_installation_values_spec.rb` reads the values in `deploy/config/sway.env` and fails if any tracked file repeats one. This repository is published, so nothing tracked may name the machine, account or paths that serve this copy.

### Why the check reads what to look for from the ignored file

Writing the values into the spec would put them back in the repository, and into its history, which is the thing being prevented.

An earlier sweep took them out of the code, and nothing then stopped them
coming back: twenty-four planning files had collected them again by the time
this check was written. So the spec reads what to search for out of the same
ignored file, rather than declaring the values it protects. The failure
message names the keys and never prints a value, because it is read in a
terminal and pasted into issues.

### Why a fresh clone shows pending rather than green

With no `deploy/config/sway.env` the examples are pending, not passing.

A fresh clone has no values to protect, so there is nothing to check, and a
quiet pass would read as "looked, and found nothing" when nothing was looked
at. The same reasoning makes the check raise rather than answer nothing when
`git ls-files` lists no files, which is how a worktree inside Docker turns up.

### Why some keys are left out of the search

A value that is also an ordinary English phrase cannot be told apart from that phrase by a substring search, so searching for it reports every innocent mention instead.

`RAILS_ALLOWED_HOSTS` and `SWAY_DEV_ALLOWED_HOSTS` hold the public site names,
which are published on purpose. `SWAY_DEPLOY_USER` is an ordinary word.
`SWAY_LITESTREAM_PATH` is a folder name any installation could pick. And
`SWAY_GCS_BUCKET_LEGISLATION` reads as a plain description of what the bucket
holds, so it matches the User-Agent this project sends to GitHub and every
planning document that names the pipeline in prose — ten tracked files, none
of them a leak.

Leaving a key out costs the one thing the check was buying for it: a genuine
leak of that value goes unreported. That is the trade the omission accepts,
because a search that reports ten innocent files every run is one an operator
stops reading, and a bucket name is a resource identifier rather than a
credential. The keys that remain all hold values specific enough for a match
to mean something.

## Why the same names are declared in the image build

Building the assets runs `assets:precompile`, and sprockets-rails makes that
task depend on `environment` — so the build starts the whole application in
production mode and this initializer runs inside it.

Every name the check requires therefore needs an `ARG` and an `ENV` in the build
stage of `docker/dockerfiles/production.alpine.dockerfile`, plus a matching
`builder.args` entry in `config/deploy.yml`. A name added to the check without
them stops the image build about four minutes in with a Ruby backtrace.
`spec/config/deploy_build_values_spec.rb` reads the initializer and both files
and fails when they disagree, so that discovery happens in the suite rather than
in a build.

These build values deliberately do not reach the running container. The final
stage never sees them and the container takes its own copies from `env: clear:`,
so changing a bucket later costs a redeploy rather than a rebuild.

## Why a missing OpenStates key stops the deploy in a hook

The OpenStates key is checked by `.kamal/hooks/pre-deploy` and not by this initializer, so a production deploy without it stops before containers switch over while the image build stays unchanged.

Maryland legislators come from OpenStates, so without the key registration would finish with only the Governor. The initializer cannot hold the check: it runs inside `assets:precompile`, so the name would need a build `ARG`, which would bake the secret into an image layer. Kamal hands the hook every secret in `.kamal/secrets-common` because `pre-deploy` runs with `secrets: true`, and the hook runs on the deploying machine, never in the image.

Only a deploy, redeploy or rollback runs it. Development and test never do, and a restart that skips hooks is not checked. A present but wrong key passes, as with the bucket names above.
