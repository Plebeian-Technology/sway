---
lat:
  mode: explanation
---

# The standby copy of the production database

`scripts/standby-restore.sh` lives on a second machine and fetches Sway's production database out of the cloud copy every night. Two of its rough edges came from the accounts involved rather than from the fetch itself.

## Installing from an account that cannot sudo

The account that owns the sign-in file, the standby folder and the docker membership is the one the timer runs as, and that account is deliberately not a sudoer.

The obvious install line, `sudo ./standby-restore.sh install`, therefore fails twice over where the owning account is not a sudoer. That account cannot sudo at all, and an account that can sudo cannot read the script when the owner's home directory is mode `0700`. Root can read it, so naming the full path to the file is what makes the command work from either account.

`sudo -E` was the other half of the same trap. It carries the caller's environment only where sudoers allows it, and where it does not the four settings vanish and the run stops with all four reported missing. Values named inline, in front of `sudo`, do not depend on that permission, which is why the header and the missing-values message both show that form.

## Why the standby fetches instead of the live machine sending

The obvious arrangement — have the replicator on the serving machine send to two places at once — is not available, so the standby pulls a copy down for itself.

The pinned version accepts exactly one destination per database, and that slot
holds the cloud copy. Measured against it directly rather than read from a
manual: a settings file listing two destinations is refused outright, and the
command-line help still advertises a list, so the help is wrong. Pulling is the
better shape anyway — nothing on the live machine changes, and no second copying
program sits beside the live database, which is the arrangement that damages
both.

What this protects against is the serving machine's disk dying, and the cloud
being slow or unreachable on the day it is needed. It does not protect against
the cloud copy itself being wrong, because that is where this copy comes from;
the separate scheduled copies to a different prefix are what covers that.

Every run is also a test of the recovery path, which is half the point: a cloud copy that
nobody has restored is a hypothesis rather than a backup. Each run proves it again and records how long it took,
which is the real recovery time.

The directory it writes to is deliberately not the one the old live database
sat in, because the change that removes that directory must not touch this copy.

## Why continuous replication and six-hourly copies both run

Continuous replication and the scheduled six-hourly copy answer different
questions, so neither replaces the other.

Replication is how a dead disk is recovered from: it copies the primary
database continuously. A six-hourly copy is a snapshot of one moment, which is
what undoes a bad migration or an accidental delete — something replication
faithfully reproduces rather than protects against. The scheduled copy also
closes a gap the boot-time backup leaves: that one runs only when a container
starts, so between deploys there can be days or weeks with no new copy. Both
run, and each deletes only its own old copies.

The background-job database is deliberately not copied, for the reason recorded
where the copied set is chosen.

## Why a deploy makes at most one backup copy

The boot-time backup is bounded to one copy per deploy by a guard rather than
running whenever the container starts.

A container that keeps crashing keeps restarting, and an unbounded rule would
make a fresh copy on every restart — filling the disk fastest exactly when
something is already wrong, and burying the last copy taken while the
application was healthy under a run of copies taken while it was not.

## Why the fetch refuses to run without its disk

The run checks that the standby folder's data disk is mounted before it writes anything, and the service unit names the same mount as a requirement.

Without that check the copy lands on the memory card the machine boots from,
fills it, and reports success — the worst of the three outcomes, because it
looks like a working backup. That can happen on any machine whose data disk is unmounted,
which is why the check is on the mount rather than on the folder: an unmounted
mount point is an ordinary writable directory.

## What check has to try, and for whom

`check` existed to answer "would a run work", and answered a different question: whether four conditions held for whoever typed the command.

Both halves of that mismatch were measured on the first machine. The standby folder was `0755` and owned by the installing account, so the account the timer runs as could enter it and could not create anything in it — and every readiness line still said yes. Writing is the whole job, so a `check` that never attempts a write is reporting on the wrong thing.

The account is the other half. The install is done by a sudoer and the fetch is done by the service account, and those are routinely different people. Answers are therefore produced by running each test as the service account, and where that is impossible from the current account the line reads `unknown` rather than borrowing the caller's own answer.

The write test creates a file where the fetch would create one and removes it again, which is why `check` is no longer described as touching nothing.
