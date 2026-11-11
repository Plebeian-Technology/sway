---
lat:
  mode: explanation
---

# How Sway::Subprocess kills a timed-out child safely

When a command run by `Sway::Subprocess.capture3` outruns its deadline, or overflows an output cap, its process group has to be signalled and reaped without blocking the caller forever.

This document explains the shutdown sequence in `.terminate` and the pid-reuse race that `.signal_group` guards against.

## Why TERM first, then KILL

`.terminate` sends `TERM` first, so the child can flush and exit cleanly, then `KILL` if it does not.

Both signals go to the whole process group (a negative pid — the child leads its own group because `capture3` spawns it with `pgroup: true`; see `docs/explanation/subprocess-deadline-design.md`).

Signalling the direct child alone is not enough. When the timeout happens while draining output, the child has already exited, and the thing still holding the pipe open is a descendant process it started. `KILL` is sent after the grace period no matter what, for the same reason: `wait_thr` only tracks the direct child, so "the child exited" is not evidence the group is empty.

## Why both waits are bounded

Both waits inside `.terminate` are bounded. The grace wait asks whether the whole group has drained, not just the direct child (see `.await_group_exit`), and the final reap gets the same time budget.

This matters because a process stuck in an uninterruptible system call does not die on `SIGKILL` until that call returns. A bare `wait_thr.join` could block for as long as an I/O stall on the Kamal storage volume lasts — the exact unbounded wait this whole module exists to remove, put back inside it, and silently: the caller has not raised `TimedOut` yet at that point, so nothing above would ever report the stall. A child that cannot be reaped in time is logged and left behind instead. Abandoning it costs one pid; blocking would cost the whole worker.

"Logged and left" is true only because `.capture3` stopped using `Open3.popen3`'s block form (see `docs/explanation/subprocess-deadline-design.md`). That form's `ensure` ran an unbounded `wait_thr.join` after `.terminate` returned, so the bound inside `.terminate` did nothing, and this same claim would have described an outcome the module did not actually produce. Switching `.capture3` back to the block form would break this method without editing it.

The abandoned child is not a zombie process. `Open3.popen_run` calls `Process.detach(pid)`, so that detached thread reaps the child whenever it does eventually exit. What is held until then is just a pid, not an un-reaped entry in the process table.

## The pid-reuse race

Both KILL sites in this module have to ask before delivering: `.terminate` sends `KILL` up to `TERM_GRACE_SECONDS` after `TERM` already killed the child and `Process.detach`'s thread reaped it.

Both KILL sites in this module have to ask before delivering: `.terminate` sends `KILL` up to `TERM_GRACE_SECONDS` after `TERM` already killed the child and `Process.detach`'s thread reaped it; `.drain_within`'s overflow KILLs fire from reader threads that do not know whether the child is still alive at all. `.signal_group` exists to make that check.

A pid belongs to its process until that process is reaped. A process-group id belongs to a group only until the last member of that group exits — after that, the kernel may hand that same number to somebody else's group. Signal 0 (`Process.kill(0, -pid)`) delivers nothing and answers exactly the question that decides whether the number is still safe to use: is there still anything in that group at all?

- An empty group means the pid has been freed, and any group now wearing
  that number belongs to an unrelated process, so `.signal_group` sends
  nothing.
- A non-empty group cannot have been recycled while it still holds
  members, so the delivery is safe to make. This keeps descendant
  signalling intact for the case where `wait_thr` has already completed
  and the thing still holding the pipe open is a child of the original
  child.

## Why .await_group_exit polls instead of sleeping the full grace period

`wait_thr.join(TERM_GRACE_SECONDS)` alone gave ZERO grace when the timeout happened while draining output: `wait_thr` has already finished by then, and the thing still holding the pipe open is a descendant process.

`wait_thr.join(TERM_GRACE_SECONDS)` alone gave ZERO grace when the timeout happened while draining output: `wait_thr` has already finished by then, and the thing still holding the pipe open is a descendant process — so TERM and KILL arrived back to back on precisely the path whose intended target is that descendant, defeating "TERM first so the child can flush and exit cleanly". Sleeping out the full grace period every time would fix that but charge every ordinary timeout a flat 5s instead, so `.await_group_exit` polls `group_alive?` instead.

## Why group_alive? treats EPERM as alive

`.group_alive?` sends signal 0 (`Process.kill(0, -pid)`), which delivers nothing and only runs the kernel's existence and permission checks.

`Errno::ESRCH` means the group is empty, so `.group_alive?` returns `false`. `Errno::EPERM` means the group still exists but is not ours to signal — which counts as "alive" for this question, since a group nobody may signal has still not drained. Treating `EPERM` as alive costs nothing extra: `.await_group_exit`'s grace period is bounded either way, so a group this process can never signal simply rides out its full grace budget rather than being reported as gone early.

## Why the grace-period spec waits for a marker file before asserting

`spec/lib/sway/subprocess_spec.rb`'s "gives descendants a real grace period" example spawns a child that ignores `TERM` (`trap '' TERM`), so it is still holding the process group when the grace period ends.

`spec/lib/sway/subprocess_spec.rb`'s "gives descendants a real grace period" example spawns a child that ignores `TERM` (`trap '' TERM`), so it is still holding the process group when the grace period ends — the only case where the grace can be observed at all. The spec waits for a marker file the child writes right after installing that trap before it starts timing, closing a race: a `TERM` that arrives before the shell has actually run `trap` kills the child outright, which would look exactly like a fix that skipped the grace period entirely.

## The gap this cannot close

A gap still exists between asking the question and delivering the signal, and nothing that has only a pid to work with can close it.

Closing it would require the whole pid space to wrap around, and the new owner to become a group leader, inside that one instant — an extremely narrow window. What `.signal_group` does close is the wide-open version of this problem: a `KILL` sent seconds after the original group had already fully drained, landing on whatever unrelated process had since taken its pid.

## See also

Cross-references to process supervision, signal escalation protocols, and orphan process avoidance architecture.

- `docs/explanation/subprocess-bounded-execution.md` — why this module
  exists at all.
- `docs/explanation/subprocess-deadline-design.md` — the deadline that
  triggers termination, and why the child runs in its own process group.
- `docs/explanation/subprocess-output-capping.md` — the other place a KILL
  can originate: an output reader thread that has overflowed its cap.
