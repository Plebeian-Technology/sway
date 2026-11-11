---
mode: explanation
summary: "Why the theme prop lambda inside ApplicationController's inertia_share needs a steep:ignore for a false-positive Ruby::NoMethod on ThemeHelper methods."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the `theme` inertia_share prop needs `steep:ignore Ruby::NoMethod`

`ApplicationController`'s class-level `inertia_share do ... end` block
builds a `theme` prop that calls `theme_preference` and `theme_id`, both
instance methods `ThemeHelper` mixes in (declared in
`application_controller.rbs`).

Steep analyzes the lambda body in `singleton(ApplicationController)`
context, since the block is evaluated at the class level, so it cannot see
that `ThemeHelper`'s methods are declared as instance methods. The methods
resolve correctly at runtime — the lambda actually runs bound to a request
instance, not the singleton class — so the suppression is scoped to this
singleton-context false positive only, not a real type gap.
