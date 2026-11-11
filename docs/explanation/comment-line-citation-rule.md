---
mode: explanation
summary: "Why comments may not cite our own files by line number, the drift that prompted the rule, the third-party exception, and why the check lives entirely inside one RSpec example."
status: agent-extracted
related: []
---
# Why comments can't cite our own files by line number

<!-- vale Vale.Spelling = NO -->

A comment that cites one of our own files by line number goes stale the
next time anyone inserts a line above it, and nothing fails when it does.

## The drift that prompted the rule

Citations like this had drifted across the repo before the rule existed.
One docstring pointed at a line beyond the end of the file it named; six
copies of one comment pointed at a line in `Legistar::Client` that had
moved; a spec pointed at a line in an adapter that is now the tail of a
comment. A reader following any of them lands somewhere unrelated and has
to guess whether the note or the code is wrong.

## The rule: cite symbols, not lines

A name survives edits above it, so comments cite symbols now — a method or
constant name instead of a line number.

## The third-party exception

Third-party citations are left alone. `open3.rb:533` and `smtp.rb:666` name
code we do not edit, at a version the lockfile pins, so the number is
stable and is the only way to point at an exact line of somebody else's
source. `spec/lint/comment_line_citations_spec.rb` tells the two apart by
asking whether a file of that basename is one of ours.

## Why the check lives entirely inside one example

Everything in the enforcing spec sits inside the example on purpose. The
type checker resolves neither a `def` inside a `describe` block nor a
constant declared beside one, so pulling these out would mean declaring
them in `sig-test/` to buy nothing.
