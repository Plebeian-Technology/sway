---
lat:
  mode: explanation
---
# Proving the tooling rather than a copy of it

Several of Sway's guards are about shell scripts, Dockerfiles and generated files rather than about Ruby, and each of them was written after a check that looked convincing had passed while the thing it described was broken.

## An assertion that cannot fail proves nothing

The recurring defect in Sway's own tests is an example that would pass whatever the code did, and it arrives in several shapes.

A fixture whose fields always move together hides a defect that swaps them, so
an example that cares which field a value came from makes them disagree.
Asserting that a key is present proves only the shape: the same assertion holds
when every value behind it is nil, which is usually the one thing the surface
exists to rule out. An absence check passes trivially on a page that was never
served the thing whose absence it checks, so a non-vacuity line establishes the
value really arrived first. A stub that can no longer change the outcome — one
standing in for a branch the code stopped taking — leaves an example that cannot
fail. And a fixture written at the wrong depth can agree with a reader that is
also wrong, which is why a fixture path is built through the same helper
production writes through rather than spelled out beside it.

## A fixture leaning on a shared counter writes its values out

Where the order of rows is what an example checks, the values that decide that order are written into the fixture rather than left to a sequence.

Factory sequences are shared across a worker, so the numbers a run happens to
reach depend on what ran before it. An alphabetical sort reads the row label,
which begins with the external identifier, and the label `bill-10-lime` sorts
above `bill-9-fuchsia` — so an example about ordering can pass or fail on which
worker picked it up rather than on the code.

## A fixture has to describe a row the system could really produce

A fixture that pairs values the pipeline can never produce together rests the examples on a situation that cannot happen.

Draft positions only exist because testimony existed first, so a draft paired
with two empty testimony columns describes a row nothing could have written.
The examples that use such a row may be about something else entirely — sending
the same request twice, or naming the right draft — and they still supply the
testimony, because a guard added later to refuse the impossible row would turn
them red for a reason unrelated to what they check.

## A safe autocorrect is still a change to read

The pre-commit hook runs the Ruby formatter with safe autocorrection only, never the everything variant, and what it fixes is re-staged as whole files.

Both halves cost something. Re-staging by file defeats hunk staging: a commit
that was deliberately partial gains the rest of the file's changes, so an author
who staged one hunk of a file has to look at what actually went in. And "safe"
is the tool's own claim about a cop, not a guarantee: one cop in the safe set
carries no explicit marking to the contrary and once rewrote a bound raw-SQL
fragment back into the shape that had reintroduced a defect — after the specs
had passed, so nothing was left to catch it.

The consequence for a reader is a rule rather than an alarm: any committed line
whose correctness depends on its exact spelling is worth re-reading after the
hook has run.

## A script is proved by running it

A check on a script runs the real script and reads its answer, rather than searching the file for the words it expects to find or repeating its parsing in Ruby.

The fingerprint of an uncommitted tree is the case that settled it. The check it
replaced looked for `export SWAY_UNCOMMITTED_DIGEST` inside the deploy script,
which passes with the code that computes the value deleted, and passes with the
lines in the wrong order. That is also why the computation lives in a script of
its own — a step buried inside a longer script is one nothing can invoke.

The same argument covers a reader of the deploy configuration: a copy of its
parsing in the spec would have gone on passing while the script itself was
broken.

## A guard asserts behaviour rather than source text

A guard that greps the implementation for a class name proves nothing about what happens at runtime, and breaks when a comment moves.

The rescue it was watching is bare, so the class name it searched for appeared
only in prose. Driving the real failure through the job and reading the outcome
answers the question the guard was asked.

## A stand-in has to have the shape the real object has

A hand-written stand-in for a library's return value is written to the shape that library really returns, including where two neighbouring calls return different shapes.

Two defects shipped green because the stand-in was more convenient than the
truth. Creating a blob returns the id as plain text, and a stand-in answering
`.sha` hid that; the repository-commits endpoint nests the tree under `.commit`
while the git-data endpoint returns it flat, and a stand-in shaped like the
first was accepted where the second was expected. Leaving a stand-in out
entirely, as the blob case now does, is the stronger form of the same
discipline.

## A stub has to name the seam the caller uses

A stub is placed on the method the code under test actually calls, not on a method that used to be called or one that looks equivalent.

Both halves of that have failed here. Stubbing the environment lookup stopped
intercepting anything once the credential moved behind its own reader, and
nothing said so — a different stub answered instead, so the example still
passed. Stubbing the backtick operator likewise stopped intercepting once the
call moved to a subprocess helper, and the run shelled out to the real
repository rather than failing.

## Cleanup has to survive an interrupt

A wrapper that starts a container removes it again on the way out, and two ordinary shell habits silently defeat that.

`exec` replaces the shell, so no trap can fire afterwards and no exit code can
be read. A foreground command holds a trap until it returns, so an interrupt
reaches cleanup only when the command is backgrounded and waited on — measured,
the foreground form leaked the container and `wait` removed it. Neither form
survives `SIGKILL`, which is the honest limit of the arrangement.

## A comment does not end a continued RUN block

Docker removes comment lines before joining a continued `RUN`, so a comment sitting inside one does not end the continuation.

A reader that tracks only the trailing backslash therefore cuts such a block in
half, and on Sway's own Dockerfile the discarded half is the one holding every
secret — so the check that reads those blocks would have reported them all
absent.

## One example lets the real converter run

Every other example replaces the subprocess call, so none of them could notice extraction itself breaking; one example runs the real binary against a real file.

Stubbing the seam is right for the branches being tested and leaves a gap
exactly where the tool meets the outside world, which is where the failures
actually happen.

That one example is also what makes the converter a requirement of the machine
rather than of the images alone. The development and production images already
carry it; a continuous-integration runner starts without it, so the workflow
installs it there. The browser system spec for the standalone PDF extraction
service does the same across the HTTP seam: it compiles the Go service in
`ops/pdf-extractor/`, boots it on a loopback port against an isolated
legislation root, and drives the Admin Bill Creator pipeline UI through a real
extraction run and a corrupt-file failure run while asserting that Rails never
invokes a local subprocess. That is why the development image and the
continuous-integration workflow also install `golang-go` alongside
`mupdf-tools`. The OCR language data is the opposite case — the spec builds
a hermetic copy of its own under a temporary directory, so nothing has to be
installed for it and no machine's system copy can change what the example
reads.
