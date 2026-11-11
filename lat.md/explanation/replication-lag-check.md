---
lat:
  mode: explanation
---
# Watching the continuous copy

Litestream copies the primary database to cloud storage as it changes, and Sway watches that copy by listing its prefix and comparing the position it finds against the one it found last time. Its whole value is that it cannot be quietly wrong.

## A promise the type system cannot hold is closed by a raise

Several of the reading's fields are declared non-nilable because one branch always sets them, and nothing in the type system ties that guarantee to the branch it depends on.

A reading's error is declared as an exception and is only really set when the
status is unreadable; the position is declared as an integer and is only really
present when the status is ok. Both statements are honest only because a runtime
check refuses the combination that would falsify them. Removing the raise does
not produce a type error — it produces a run that dies later on a nil
comparison, a long way from the reader that broke the promise.

The status itself is the same shape from the other side. Only a caller
bypassing the declared union can reach the unrecognised branch, so the raise
there is the only thing that closes it, and the example that proves it has to
pass a deliberately untyped value. The union stays on the constructor, where it
holds every checked caller to the three symbols; the reader that the branch
reads is declared a plain symbol, because a bypassing caller is exactly what
that branch exists to catch, and a reader narrowed to the three would make the
branch dead by declaration while it is alive in fact.

## Why the two values are asserted together

One assertion compares both the prefix handed to the listing and the value recorded on the reading against the same literal.

Asserted separately against each other, the two can silently agree while both
are wrong — which is the failure a watcher is least able to notice, because a
watcher that has never seen a copy and a watcher watching the wrong place
produce the same output.
