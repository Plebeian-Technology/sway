---
mode: explanation
summary: "Explains why ReportApplicationErrors#application_errors duck-types RSpec's two multi-exception shapes instead of matching a shared class, and why it strips the exception's own self-reference from the list."
status: agent-extracted
related: []
---

# Why `ReportApplicationErrors#application_errors` duck-types RSpec's multi-exception shapes

`ReportApplicationErrors` relays an error that escaped into a spec
example to Sentry, tagged with the test that produced it. A
failed expectation is about the test itself, not a bug in the app, so it
is filtered out rather than sent (see `.test_failure?` and
`TEST_FAILURES`).

RSpec can hold several failures in one exception object — for instance
when `aggregate_failures` runs several expectations and more than one
fails — so `.application_errors` has to recurse into that container rather
than treat it as a single error, so a real application error sitting
beside a merely-failed expectation still gets sent.

## Why the recursion is duck-typed on `respond_to?(:all_exceptions)`

The two shapes RSpec uses for "more than one exception" share no common
class or module: measured, `MultipleExceptionError` includes
`InterfaceTag` while `MultipleExpectationsNotMetError` does not, yet both
respond to `#all_exceptions`. There is no shared ancestor to `is_a?`
against, so the method checks for the method instead of the type.

`spec/support/report_application_errors_spec.rb`'s "opens an
aggregate_failures bundle too" example exercises `MultipleExceptionError`
specifically — a different class sharing no module with
`MultipleExpectationsNotMetError` — because an earlier draft of this check
matched RSpec's marker module instead of duck-typing on the method, and
silently missed every case of this second shape. The example builds a
REAL `aggregate_failures` bundle rather than a faked one, because
`#all_exceptions` is added to the class only when that code path first
loads — a verifying test double of the class refuses to answer a method
that was never actually defined on it, so a fake bundle would not catch a
regression here.

## Why the exception subtracts itself from its own exception list

`Array(exception.public_send(:all_exceptions)) - [exception]` removes the
container exception from its own list of inner exceptions. Some of these
objects list themselves among their own `all_exceptions`, and recursing
into an object that lists itself would recurse forever without that
subtraction.
