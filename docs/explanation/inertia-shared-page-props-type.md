---
mode: explanation
summary: "Why the global sway.IPageProps interface in app/frontend/index.d.ts exists, and how it relates to ApplicationController's inertia_share."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why `sway.IPageProps` exists

The props Inertia shares with every page (flash and errors) live on this
global `IPageProps` interface, so a page can read
`usePage<sway.IPageProps>().props.flash` without casting the type itself.
Rails sends flash through `inertia_share`, and errors through the
`inertia: { errors: ... }` option on a redirect.
