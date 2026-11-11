---
mode: explanation
summary: "Explains why Sway::Subprocess.capture3 enforces one wall-clock deadline across both child exit and output draining, and how each timing constant supports that."
status: agent-extracted
related: ["docs/explanation/subprocess-bounded-execution.md", "docs/explanation/subprocess-output-capping.md", "docs/explanation/subprocess-termination-and-pid-reuse.md"]
---

# How Sway::Subprocess enforces its deadline

<!-- vale Vale.Spelling = NO -->

`Sway::Subprocess.capture3` (`lib/sway/subprocess.rb`) promises that a
command cannot run past its timeout. This document explains why that
promise needs one deadline covering the whole call, not just the child
process, and why each timing constant has the value it has.

## Why the timeout is generous

`DEFAULT_TIMEOUT_SECONDS` is 300 (5 minutes), on purpose. The limit exists
to turn a hang into a loud failure, not to police slow but legitimate work:
`mutool` rendering a large scanned PDF at 300 DPI on the single production
arm64 Pi takes minutes, not seconds.

One deadline covers every call site, rather than a table of per-command
values. A table tempts the next reader to tune one entry and leave the
rest — exactly the kind of mistake this code kept attracting before this
design.

## Why the deadline has to cover draining, not just child exit

An earlier version passed `timeout_seconds` only to `wait_thr.join`, which bounds
child exit. After the child exits, the stdout/stderr reader threads block
with no deadline until the pipes reach end-of-file — and that needs every
descendant process holding the inherited write end of the pipe to exit too.

This was measurable: `capture3("sh", "-c", "sleep 8 & exit 0", timeout_seconds: 1)`
returned after 8.02 seconds and raised nothing. `mutool` and `tesseract` do
not fork, so this gap was never hit in production — but a public method
documented as `@raise [TimedOut] when the child outruns the deadline` has to
mean it, because the whole point of the bound is to turn "hangs forever"
into "fails loudly." `Sway::Subprocess.capture3` now measures one deadline
from the monotonic clock and uses it for both waits.

## Why the child runs in its own process group

`capture3` spawns with `pgroup: true`, so the child leads its own process
group. The deadline exists to free the pipes, and signalling only the
direct child would leave a descendant process — the thing actually holding
the pipe open — untouched. A negative pid signals the whole group at once.
See `docs/explanation/subprocess-termination-and-pid-reuse.md` for how that
signal is actually delivered.

## Why capture3 uses popen3 without a block

`capture3` calls `Open3.popen3` without a block and does its own cleanup,
rather than using the block form. The block form was defeating the whole
bounded-shutdown design.

Ruby's `Open3.popen_run` ends its `ensure` with an unbounded `wait_thr.join`
(`open3.rb:533-546`):

```ruby
if defined? yield
  begin
    return yield(*result)
  ensure
    parent_io.each(&:close)
    wait_thr.join            # <- no limit
  end
end
```

`raise TimedOut` inside the block would therefore unwind straight through
that `ensure` and block there, for as long as the child took to die. The bounded
reap that `.terminate` performs bought nothing: the comment on `.terminate`,
the RBS types, and its own examples all claimed a property `.capture3` did
not actually have. The examples could not catch this because they call
`.terminate` directly with a test double, and every `.capture3` timeout
example used a child that dies promptly on `KILL`. This was also
measurable: `Open3.popen3("sh", "-c", "sleep 3") { raise }` returned after
3.02 seconds.

Without the block form, `capture3`'s `ensure` only closes the parent's ends
of the three pipes — the half of `popen_run`'s `ensure` that actually
matters, since skipping it would leak three file descriptors per call — and
does not join. No join is needed: `popen_run` calls `Process.detach(pid)`
before handing back `wait_thr`, so that thread reaps the child whenever it
does eventually exit. An abandoned child costs one pid and leaves no zombie
process, matching `.terminate`'s "logged and left" promise (see
`docs/explanation/subprocess-termination-and-pid-reuse.md`).

## Why reader joins get a floor, not just the remaining time

`DRAIN_FLOOR_SECONDS` is 0.25 seconds. It is the minimum time allowed for
the two output-reader thread joins, and only for those two joins, and only
after `wait_thr` has already returned.

Once `wait_thr` returns, the child is gone and the pipes are at, or one read
away from, end-of-file — so these joins are waiting for a thread to be
scheduled, not for a process to finish. `Thread#join(0.0)` is a poll, not a
wait. Without a floor, a deadline that ran out on the same tick as the
child's exit made `capture3` kill an already-dead process and raise
`TimedOut` over output it was already holding in memory, discarding it.

A quarter of a second is orders of magnitude more than a scheduling slice,
and three orders of magnitude under `DEFAULT_TIMEOUT_SECONDS`, so it cannot
turn a real hang into a wait: a reader that is genuinely stuck — because a
descendant process still holds the write end of the pipe, the exact case
this whole deadline exists for — still raises `TimedOut`, at most 0.5
seconds later than it otherwise would.

The floor is used instead of the plain remaining time specifically because
the child has already exited by the time these two joins run. Using the
remaining time alone would answer "not finished" for a reader thread that
is merely waiting to be scheduled, not for one that is stuck — and treat a
child that exits on the same tick as the deadline as a timeout, throwing
away output it already captured.

## Why `.drain_within` is split out from `.capture3`

`.drain_within` is the body of `.capture3`, pulled out into its own method
so the deadline logic keeps its declared tuple return type. With `popen3`'s
block form gone, `.capture3`'s body is a `begin/ensure`, and the type
checker (steep) treats the value of that construct as `Array[untyped]`
instead of carrying the declared tuple through it — so folding this back
inline would cost either a type error or an annotation on every local that
feeds the return.

## Why a separate spec proves the child is abandoned, not just that the timing bound holds

`spec/lib/sway/subprocess_spec.rb`'s "leaves the unreapable child running
rather than waiting it out" example is the other half of the same claim the
"returns within its own bound" example makes, and the one the module's own
docs state outright: the child is ABANDONED, not waited on. Without this
example, a fix that only shortened the wait would still pass the timing
test alone — proving `.capture3` returns quickly says nothing about whether
it did so by killing the child or by giving up on it. The example checks
that the child is still alive (`Process.kill(0, child_pid)` does not raise)
right after `.capture3` has already returned, which is the whole claim.

## Why the "child will not die" spec fakes the signal rather than spawning an uninterruptible one

`spec/lib/sway/subprocess_spec.rb`'s "returns within its own bound when the
child will not die" example stubs `.signal_group` to do nothing, rather
than spawning a real child stuck in an uninterruptible sleep (a kernel-level
state that does not die on `SIGKILL` until its system call returns). Faking
the signalling models that exact failure mode without having to manufacture
a real one, driven through `.capture3`'s public method rather than around
it — the same shape `SubprocessSpecHelpers::UnreapableWaiter` uses for
`.terminate`'s own specs.

## See also

- `docs/explanation/subprocess-bounded-execution.md` — why this module
  exists at all, and why commands are never passed as shell strings.
- `docs/explanation/subprocess-output-capping.md` — why stdout and stderr
  are drained concurrently and capped in size.
- `docs/explanation/subprocess-termination-and-pid-reuse.md` — how the
  process group is signalled once the deadline is reached.
