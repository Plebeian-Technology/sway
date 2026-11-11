---
lat:
  mode: explanation
---

# scripts/dip/verify.sh: lane contract design

`scripts/dip/verify.sh` must clean up after itself and prove its three-state (green / red / did-not-complete) contract structurally.

It is modeled on `scripts/dip/rspec.sh` (see [[docs/explanation/dip-rspec-cleanup-container-trap.md|Why scripts/dip/rspec.sh backgrounds its compose run]]), but runs several lanes at once, so `spec/scripts/dip_verify_cleanup_spec.rb` adds lane-dispatch, process-group, container-naming, sweep-ordering and argument-refusal checks the single-lane analog does not need.

## Why pinned_lane_names is a let, not a bare constant

The full lane list is pinned literally in the spec, and has to be updated in the SAME commit that adds or removes a row from `verify.sh`'s own `LANE_NAMES`.

The full lane list is pinned literally in the spec, and has to be updated in the SAME commit that adds or removes a row from `verify.sh`'s own `LANE_NAMES` — that is the point of pinning it: a lane silently dropped from the script must turn the example red, not slide through unnoticed. It's a `let` rather than a bare constant because RuboCop's `Lint/ConstantDefinitionInBlock` flags a constant assigned directly inside a `describe` block, and `let` is the pattern the file's other two shared values (`verify_script`, `verify_runnable_lines`) already use.

Deleting a row, one at a time, makes the "declares every lane in the pinned list" example fail for the reason it names, and restoring the row makes it pass again:

- deleted `"steep"` from `LANE_NAMES` -> `lane(s) missing from
  scripts/dip/verify.sh: \["steep"]`
- deleted `"rubocop"` from `LANE_NAMES` -> `lane(s) missing ...:
  \["rubocop"]`
- deleted `"tessdata-parity"` from `LANE_NAMES` -> `lane(s) missing ...:
  \["tessdata-parity"]`

A guard that passes whether or not a lane is present is worse than no guard, because it reports green while checking nothing.

## Why declared_lane_names never returns nil

Even when no `LANE_NAMES=( ... )` array is found, `declared_lane_names` returns `[]` rather than `nil` so every caller only has one not-empty check to make.

Steep cannot narrow `Array[String] | nil` from an RSpec `not_to be_nil` matcher, so a nilable return here would leave every later `.tally`/`-` call a real `NoMethodError` against `nil` under the `:test` Steep target. `run_lane_case_labels` follows the same rule for the same reason: the `*)` catch-all is deliberately not counted as one of the labels — it is not a lane.

## Why lane_array_entries parses arrays the way it does, and what was measured

Deleting `trap cleanup EXIT INT TERM` from `scripts/dip/verify.sh` makes the "registers cleanup" example fail; restoring the line passes it again.

`lane_array_entries` reads entries of one of `verify.sh`'s index-aligned lane arrays. Quoted arrays hold strings with spaces in them, so those are counted by quote pairs and the bare ones by whitespace. It never returns nil, for the same reason `declared_lane_names` does not.

## Why all five index-aligned lane arrays must stay the same length

`LANE_LOG` and `LANE_RERUN` are read with a plain `${...[$idx]}`, so a short array fails loudly under `set -u`.

`LANE_CONTAINER` is read with `:-`, so a misalignment there is silent: insert a lane in the middle of `LANE_NAMES` and append its container name at the end of `LANE_CONTAINER`, and every Docker lane after the insertion point takes another lane's container name — cleanup then removes containers belonging to other lanes and misses its own.

## Why cleanup kills process groups, not only containers

Bash gives an asynchronous command in a non-interactive shell an ignored `SIGINT`, so a terminal Ctrl-C reaches this script and not its lanes.

Sending `SIGINT` to a whole process group the way a terminal does makes the parent run cleanup and exit, while its backgrounded child runs to completion afterwards.

`cleanup()` signals every lane's process group with `kill -TERM "-${LANE_PID...`, not only its container — an interrupted run otherwise leaves every host lane running, and the rbs-validate lane goes on to rewrite the tracked `rbs_collection.lock.yaml` after the user has their prompt back. It also signals `INSTALL_PID` and `BUILD_PID`, the dependency-install and frontend-build barriers — an interrupt during either leaks the same way.

A negative pid names a process group, and a lane only has its own group when job control is on: without `set -m` every lane shares this script's group, `kill -TERM -$pid` fails outright, and the tool the lane started survives.

## Why the container sweep age-gates instead of removing by container state alone

No lane carries `--rm` any more, so a live run's finished lane container sits in `exited` state from the moment that lane ends until that run's cleanup fires at the very end — most of the run, for a fast host lane.

Two runs are meant to overlap, so an ungated sweep in the second run removes the first run's containers before it has read their exit code and out-of-memory flag, which is the dead-inspect state dropping `--rm` existed to fix. A `created` container is worse still: that state lasts milliseconds while another run is starting a lane, and force-removing it kills a lane that was about to run.

## Why no lane container carries --rm, separately from the sweep

`--rm` removes the container as part of the run, so `classify_lane`'s `docker inspect` would find nothing (it reports "no such object") and the branch that turns an out-of-memory kill into `did-not-complete` could never fire.

`--rm` removes the container as part of the run, so `classify_lane`'s `docker inspect` would find nothing (it reports "no such object") and the branch that turns an out-of-memory kill into `did-not-complete` could never fire — an OOM-killed rspec lane was reported red with whatever example count one worker happened to print. `cleanup()` owns the removal instead, once `classify_lane` has had its chance to read the container.

## Why bash's case fallthrough makes an explicit catch-all mandatory

A `case` that matches no label runs nothing and returns 0:

```
bash -c 'f(){ case "$1" in a) echo A;; esac; }; if f zzz; then echo GREEN; fi'
-> GREEN
```

So a lane declared in `LANE_NAMES` with no branch in `run_lane()` is recorded exit 0 and classified green having run nothing, which is the exact failure this whole gate exists to remove. `run_lane()`'s `*)` catch-all has to return an exit code outside `{0,1}`, so an unmatched lane is classified `did-not-complete` — the honest state for a lane that never ran — rather than green or red.

## Why the browser lane alone carries SWAY_REQUIRE_BROWSER=1

A missing browser fails the run instead of shrinking it.

With `spec/support/system_driver.rb`'s `CHROME_CANDIDATES` pointed at a single nonexistent path, a real `dip run verify` exits 2 (rspec-browser red at the `assert_available!` raise) rather than exiting 0 with fewer examples. Only the browser lane may carry `SWAY_REQUIRE_BROWSER` — a shard that loses its browser would otherwise drop its examples and the run would still report green.

`SystemBrowserPreflight.required?` (`spec/support/system_driver.rb`) reads this as an exact string comparison, `ENV["SWAY_REQUIRE_BROWSER"] == "1"`, rather than a truthy check, so an accidentally exported empty value or `"0"` leaves the ordinary skip-when-missing behavior in force — the skip is a kindness for focused runs and for machines that legitimately have no browser, and only `verify`'s browser lane should ever turn it off.

## Why both rspec lanes need their own SWAY_TEST_DATABASE_DIR

Per-worker database isolation holds under real load.

While a real `dip run verify`'s rspec-nonbrowser container is running, `/testdb` lists one distinct, non-empty SQLite file per worker, and no lane log shows `SQLite3::BusyException`, including for two runs started seconds apart. Without `SWAY_TEST_DATABASE_DIR` set per lane, both rspec lanes' workers would fall back to the shared `storage/test.sqlite3` and collide with every other run on the host.

## Why the two rspec lanes each name themselves in SWAY_TEST_LANE

The two rspec lanes run at the same time, in two containers that bind-mount the same checkout, and `TEST_ENV_NUMBER` restarts at 1 in each lane.

Without the lane in the name, both lanes' worker 2 claim the SimpleCov key `"rspec-worker-2"`, and SimpleCov merges by name — one lane's slice replaces the other's instead of joining it. `spec/rails_helper.rb` has to put the lane in SimpleCov's command name too — these two files have to agree, or passing `SWAY_TEST_LANE` from `verify.sh` changes nothing.

## Why brakeman's exit codes are read specially in classify_lane

Brakeman does not use 0/1 for its results.

From its own `lib/brakeman.rb` (8.0.6): `Warnings_Found_Exit_Code = 3`, `Errors_Found_Exit_Code = 7`, both raised by `lib/brakeman/commandline.rb` under the `--exit-on-warn` and `--exit-on-error` flags this lane runs with. Classified by the shared 0-or-1 rule, a real security finding would read as "the lane crashed, re-run it" instead of red.

## Why the rbs collection install barrier must run before any lane starts

`rbs collection install` rewrites `rbs_collection.lock.yaml` in its own YAML style even when nothing it installs changed, and the oxfmt lane reads that same file.

Started inside a lane, or anywhere after the lanes are running, the two race: on a clean tree oxfmt could report a violation in a file nobody touched, and a re-run would pass.

The guarding spec example catches two mutations: deleting only the barrier's own `bundle exec rbs collection install &&` line, and moving the whole barrier below the lane-start loop. Each turns the example red with its own message. A plain substring search, which this example's line-order check replaced, survives both mutations, because `LANE_RERUN`'s copy-pasteable rerun string carries the same words — so the check has to be anchored to the start of a line, and has to compare line order, not just presence.

## Why verify.sh takes no lock around any lane

Two `dip run verify` invocations started a few seconds apart both run to completion.

No lane log shows `SQLite3::BusyException`, example totals match between the two runs, and both runs' build directories under `public/vite-test` are present and distinct at the same time. This is what the "no lock, two runs must both stay valid" decision predicts, and it holds under real concurrent load, not just in isolation. A `flock` call or an explicit lock-mode constant would serialize two verify runs against each other, contradicting that decision.

## Why the three-state decision lives in verify-lib.sh, not in this spec

A lane that selects no examples is did-not-complete, never green.

With `sway:test:lane`'s nonbrowser branch temporarily pointed at a directory with no spec files, a real `dip run verify` reports `rspec-nonbrowser examples: 0, state: did-not-complete` in `summary.json`, and the whole run exits 2 — not 0, and not counted as a red test failure. Restoring the file selection returns the lane to its full example count.

The three-state decision itself moved to `scripts/dip/verify-lib.sh`, and `spec/scripts/verify_lane_state_spec.rb` calls it with fixture values rather than matching this script's text — including the two cases a text match could never separate: a lane that ran zero examples, and one that counted failures and still exited 0. What stays true of `dip_verify_cleanup_spec.rb` is only that it still asks `lane_state` for the answer.

## Why verify.sh prints progress lines during the barriers and each lane

The design keeps lane OUTPUT off the screen and rules out a live status board, which redraws and degrades in a non-TTY.

It never ruled out append-only progress lines, and without them a person watching this gate sees nothing at all between starting it and its summary — minutes, across three barriers and two multi-minute lanes, with no way to tell a working run from a hung one. Each of the three barriers that run before any lane starts announces itself (`progress "barrier N of 3..."`) for the same reason.

Every lane is handed the terminal as fd 3 ahead of its log redirect (`3>&2 >"${LANE_LOG...`), so its completion line is not swallowed by its own log file — without it that lane finishes in silence, and under `set -e` a closed fd 3 aborts the wrapper before it can stamp `.lane-end`, which also breaks the duration that lane reports. `run_lane_wrapped()`'s completion `printf` writes to fd 3 rather than the lane's own stdout or stderr for the same reason, and deliberately never prints a verdict (red/green/did-not-complete): the wrapper cannot read the container, a lane killed for memory exits non-zero and is `did-not-complete`, not red, so a verdict here would contradict the summary table below it — only `classify_lane` may decide.
