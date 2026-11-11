---
lat:
  mode: explanation
---
# What a continuous-integration run assumes about its machine

The workflows do not name the machine they run on. Which machine answers decides both which Ruby resolves and how much of the suite actually executes, and neither of those announces itself in a run's log.

## Why no workflow names its machine

Each workflow reads the `CI_RUNNER` repository variable and falls back to `ubuntu-latest` when it is unset, which is what a fresh clone and every fork see.

Setting the variable is how a copy of the repository targets a particular
runner, such as a self-hosted machine. A workflow that wrote a self-hosted
runner into the file would hand every other copy of the repository a job that
queues forever with no machine to take it. Naming the exception in a variable,
rather than the rule in the file, leaves the default case as the safe one.

### Why a runner without a browser still reports green

System examples need a Chromium binary and its driver at the paths `SystemBrowserPreflight` looks in, and where neither is present those examples skip while the rest of the suite runs.

The run then reports green having tested less, and nothing in its log says so.
On x64 the workflow installs a browser itself, so the gap belongs to the
machines it cannot install one on.

## Why the runner's Ruby comes from the host toolchain

On a self-hosted macOS runner the standard setup action is passed over, because its prebuilt macOS rubies are hardwired to the GitHub-hosted tool-cache prefix and fail with a permissions error anywhere else.

The host's own toolchain answers instead, and `Gemfile.lock` already matches the
development environment, so installing gems there is a fast no-op check rather
than a build. A hosted machine has neither that toolchain nor a runner-user home
folder to read shims from, so it takes the action's path; `.ruby-version` is the
one pin on either machine.

That the shim reads `.ruby-version` and nothing else was checked rather than
assumed: in a directory holding `.ruby-version` alone, it resolved 4.0.7. The
repository does carry a `mise.toml`, but its `ruby` entry names `latest` rather
than a version, so it is not a second pin the file could disagree with — the
same reason [[toolchain-pins#Why Ruby and Python are exempt from the same check|Ruby is exempt from the pin-agreement check]].

The Brakeman workflow carries the same setup step, byte for byte, and the two
have drifted into the same failure twice: a fix applied to one of two identical
blocks leaves the other broken, and nothing connects them but the intention to
keep them alike. Both therefore point here rather than restating the reasoning,
so a correction has one place to land even though the step itself is duplicated.

### Why the shim directory is proved before it is trusted

A directory that does not exist is still accepted on `PATH` without complaint, so a version manager that has been uninstalled fails quietly rather than loudly.

Prepending an absent directory changes nothing, so a setup step that only
extends `PATH` would go on reporting success while `ruby` fell through to the
system copy, and every Ruby lane would then die at bundle install with a
Gemfile version mismatch.

That is the same exit code, and the same misreading of a setup failure as a test
failure, that an emptied `.ruby-version` produces, because the version manager
then falls through to each machine's global Ruby. The shim path is therefore
tested for an executable Ruby, and the version it resolves is compared against
the repository's pin, before a bundle install is spent on either.
