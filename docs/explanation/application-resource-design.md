---
mode: explanation
summary: "Why ApplicationResource enforces an explicit field allowlist instead of as_json, and why alba-inertia's controller shortcut is not wired up."
status: agent-extracted
related: [serializer-whitelist-endpoints]
---

<!-- vale Vale.Spelling = NO -->

# Why `ApplicationResource` exists

## Why an explicit field allowlist instead of as_json

Each Alba resource subclass lists the exact fields a record may expose,
instead of Rails' `as_json` dumping every column.
See [Why these endpoints serialize through a whitelist resource](serializer-whitelist-endpoints.md)
for the leaked-columns risk that motivated this rule.

## Why alba-inertia's controller shortcut is left off

alba-inertia's controller shortcut (`render_inertia` auto-picking a
resource) is deliberately not wired up — see the note beside the
`alba-inertia` gem line in the `Gemfile`: it replaces the prop-hash
pattern `render_inertia_or_json` depends on, and the plan is to revisit
once the gem matures past 0.1.x.
