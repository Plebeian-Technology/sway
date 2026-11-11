---
lat:
  mode: explanation
---

# Why Sway::Subprocess exists

`Sway::Subprocess.capture3` (`lib/sway/subprocess.rb`) is a drop-in replacement for `Open3.capture3` that adds a hard deadline and blocks shell injection. This document explains why both of those exist.

## The problem: Open3.capture3 waits forever

Both PDF extractors in the legislation pipeline shell out to `mutool`, and one of them also shells out to `tesseract`, on documents supplied by members of the public.

A malformed PDF that makes `mutool` spin blocks the `fetch_hearings` stage indefinitely — twice, because `FetchHearingsService#attempt_extraction` retries once. Nothing above it in `RunLegislationPipelineJob` watches the clock, so a single bad PDF can hang a pipeline run forever.

`Timeout.timeout` around `Open3.capture3` does not fix this. It interrupts the calling thread, but `capture3`'s own `ensure` block joins the child's wait thread. The interrupt just blocks somewhere else while the child keeps running. The child process itself has to be signalled to stop, which means using `popen3` directly instead of `capture3`'s block form. See `docs/explanation/subprocess-deadline-design.md` for how the deadline is actually enforced.

## The problem: shell strings let a filename become a command

Commands are passed to `Sway::Subprocess.capture3` as separate arguments (argv), never as one shell string. That is what stops a hostile PDF filename from smuggling in shell characters.

This rule used to be written down but not enforced. Ruby hands a command to a shell when it arrives as a single string containing shell characters, so `Open3.capture3("echo x > /tmp/f; echo INJECTED")` really does run a shell and really does create the file. `Sway::Subprocess.capture3` makes that impossible by construction, in its `.argv` helper.

## How .argv closes the gap

Ruby only consults a shell when the command it is given is a single String.

`Sway::Subprocess.argv` checks for exactly that case — a one-element command array whose element is a String — and rewrites it as `[[binary, binary]]`. That is `Process.spawn`'s explicit "this is the executable to run, and this is what should appear as `argv[0]`" form, and Ruby never hands that form to a shell.

The result: a legitimate command with no arguments still runs, because the binary is still named correctly. A string full of shell characters instead becomes a failed exec — a `SystemCallError`, which every caller already knows how to translate into its own failure type — instead of a shell command that executes whatever the string contained.

## See also

Related architectural documentation detailing process supervision, execution limits, and cleanup mechanisms.

- `docs/explanation/subprocess-deadline-design.md` — how the wall-clock
  deadline is enforced across both child exit and output draining.
- `docs/explanation/subprocess-output-capping.md` — why stdout and stderr
  are also capped, and why `OutputTooLarge` carries stderr.
- `docs/explanation/subprocess-termination-and-pid-reuse.md` — how a
  timed-out child's process group is killed safely.
