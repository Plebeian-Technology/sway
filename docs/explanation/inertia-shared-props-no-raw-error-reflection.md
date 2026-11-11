---
mode: explanation
summary: "Why the shared inertia_share params prop deliberately omits an errors: params[:errors] key, to close a reflected-text injection hole."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the shared `params` prop has no `errors` key

`ApplicationController`'s `inertia_share` block ships a `params` prop
carrying `sway_locale_id`, but deliberately no `errors: params[:errors]`
key. Reflecting that value would let a crafted `?errors=` link inject
arbitrary text into page props, and nothing on the frontend or mobile ever
read it anyway. Flash is the sanctioned error channel in this app; nothing
else earns a path from a raw query parameter into rendered props.
