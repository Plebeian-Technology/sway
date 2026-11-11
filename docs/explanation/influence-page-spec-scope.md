---
mode: explanation
summary: "What spec/system/influence_spec.rb covers for the Influence page and its redirects, and why the two redirect branches are deliberately left to a request spec instead."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# spec/system/influence_spec.rb scope

The Influence page (`/influence`) and its redirects had no browser
coverage before this spec. `InfluenceController#index` shows the influence
page to a user who finished registering, sends a user who has not back to
registration, and sends a user with no locale to the home page.

House rules for browser tests in this file: never sleep, and give anything
that takes time a `wait:`. Logging in runs the real passkey ceremony
against a fake browser authenticator, the same way the voting and login
specs do.

## Why the two redirect branches are not driven in the browser

Getting the browser into a signed-in-but-unfinished-registration state
fights the registration state machine and the locale lookup. Those two
redirects are short controller branches (`influence_controller.rb`) that a
request spec covers better, so they were filed as follow-up work instead
of living here as a flaky browser example.
