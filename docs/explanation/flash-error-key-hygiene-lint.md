---
mode: explanation
summary: "Why spec/lib/flash_keys_spec.rb bans flash[:error] outright rather than warning, and why its check matches across newlines."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `flash[:error]` fails the build

`app/frontend/sway_utils/flashToasts.ts` only shows `flash[:notice]` and
`flash[:alert]`. A controller that sets `flash[:error]` instead has its
message dropped without a word — the user sees nothing at all, and nothing
in the response looks wrong.

`spec/lib/flash_keys_spec.rb` fails the build on any controller matching
`flash[\s*:error\s*]`, including a multi-line form:

```ruby
flash[
  :error
] = "..."
```

The pattern's `\s` matches newlines, so this catches the same offense a
line-by-line search would miss.
