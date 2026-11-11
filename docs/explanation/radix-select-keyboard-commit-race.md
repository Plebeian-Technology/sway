---
mode: explanation
summary: "Why a keyboard-driven Radix Select commit must send the final Enter to the button in one WebDriver call, not a separate focus then send_keys."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Committing a Radix Select by keyboard in Capybara

Capybara's `find(:button, ...).send_keys(:enter)` both finds the save button
and sends it Enter in one call. `find` retries until the button is really
there and fails naming it if it never arrives — a button not yet on screen
used to focus nothing and leave a submit no one ever asked for.

It has to be one call, not focus-then-separately-send-Enter. Radix keeps the
listbox mounted through its close animation and only then sends focus back
to the trigger (`onUnmountAutoFocus` in `@radix-ui/react-select`). That runs
on a real animation-end event, so `page.execute_script(focus)` followed by a
separate `page.send_keys` can have Radix's own refocus land in between and
steal focus back to the trigger, which then reopens on Enter instead of
submitting — reproduced deterministically by forcing a delay between the two
calls. `send_keys` on the button itself focuses and keys it in one WebDriver
round trip, leaving no gap for Radix to land in.

## Finding a Radix Select's trigger and its options

Radix renders the option list into a React portal outside the trigger
element's part of the page. Find the trigger by `role="combobox"` and the
options, wherever they landed in the DOM, by `role="option"`.

## Focusing the trigger with JavaScript instead of Tab

Tabbing through the surrounding page layout to reach a Select trigger is
unreliable in chromedriver. Focusing the element directly with
`page.execute_script` is the documented Capybara way out for keyboard tests.

## Waiting for the highlighted option, not for the option itself

An option is on screen the moment the listbox opens, so `find` returns it
straight away — reading `data-highlighted` off it then samples the page
before an arrow-key press has moved anything, a race that failed roughly
one run in four. Asking Capybara to match on the `data-highlighted`
attribute makes it retry until the highlight actually lands, which is the
thing that kind of assertion is about.

## The [role='option'] technique unblocked a previously-skipped spec

`spec/system/bill_category_override_spec.rb`'s per-bill category override
test was skipped at first because its Radix Select dropdown was flaky to
drive from a browser test. The admin LLM settings spec (above) later showed
that clicking the dropdown's `[role='option']` entries works reliably, so
the category-override spec was un-skipped on the strength of that finding.
Its override controls only render for a bill that already has a summary,
so the spec creates a completed `BillLlmProvisioning` row.

## Why some admin system specs cover a keyboard-only path at all

The accessibility behavior of Radix Select is the part most likely to
break — a future shadcn upgrade, or a change to the app's own Select
wrapper, could break the Tab, Space, ArrowDown, Enter sequence admins rely
on. A mouse-only example proves the happy path; a keyboard-only example
proves the same journey ends up in the same place by keyboard.
