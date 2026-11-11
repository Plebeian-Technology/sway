---
lat:
  mode: explanation
---
# What the development server watches

The development server reloads a browser when a file it is watching changes, and two of its defaults are wrong for this repository: it watches files a machine writes, and its ignore list does not work the way it reads.

## Why a machine-written file must not be watched

Vite treats every HTML file it watches as a page, so a change to one sends a full reload to every open browser.

The test suite writes a coverage report on every run, and agents run the suite
inside linked checkouts under the repository (`.claude`, `.agents`, and `.worktrees`), so their reports do it too — the
container logged twenty-one of these reloads in one session, and descending into worktree checkouts, `.pnpm-store`, or `legislation` runtime artifacts exhausts the container's file-watcher limit (`ENOSPC`). It is more than an
interruption: a reload throws away whatever is on screen, a half-typed piece of
testimony or an unsaved edit, and it destroys evidence, because a hands-on test
proving that no screen needs a manual refresh cannot tell a reload sent from
outside from the product reloading itself. `coverage` and `node_modules` are also matched at any depth in case a worktree or package folder sits outside the top-level directories, while `public/` remains watched because it holds the static Rails error pages.

## Why the ignore list is a function and not a list of patterns

The obvious spelling of an ignore rule is a glob, and a glob here does nothing at all.

Measured against the file watcher this project ships, by watching a real
directory and changing a real file in it: with no ignore rule the change is
seen; with the glob the change is still seen; with a directory entry or a
function the change is not. The reason is one line in the watcher — a string
matcher becomes an exact comparison, so stars are not special to it and a
pattern can never match a real path. An ignore list written in patterns is
silently switched off while looking correct.

The same line means the watcher's own built-in ignores are dead for the same
reason, which is why the list restores them by hand rather than assuming they
are handled.

## A reload a plugin sends says so

Vite prints a line for the reloads it decides and prints nothing for a message a plugin sends itself, so the plugin logs its own.

An unannounced reload reached every open browser and left no trace on either
side. A reload nobody can account for cost a day of investigation, which is
more than the log line costs.

## Whether a build uploads source maps

Three values decide it, and all three have to be present so that a build carrying only some of them does not half-upload.

The production image supplies them; a preview build and a plain local image
build do not, and both still have to succeed. This used to be moot for a
different reason — the dockerfile assigned the token without exporting it, so it
never reached the build process and no build had ever uploaded anything.

## Why the ignore rule is tested in both directions

The rule has to be wrong in only one direction to be useless, so its test checks both what is ignored and what is still watched.

Ignoring too much stops an edited template from reloading the page, with no
error to say so; ignoring too little brings back the machine-written reloads
above. A test of one direction alone would pass for a rule that ignores
everything, or for one that ignores nothing. So the test lists paths on both
sides, and the file that started it — a coverage report written by a test run
in an agent's worktree — has an example of its own.
