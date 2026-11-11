---
lat:
  mode: explanation
---

# What wait_until_loaded proves

`wait_until_loaded` in `spec/support/capybara_helpers.rb` waits for the Inertia progress bar (`#nprogress`) to be gone from the page. It proves an absence, which is weaker than it looks.

## Why waiting for an absence can pass instantly

In the common case the progress bar has not been put on the page yet when the helper runs, so the wait is already satisfied and returns immediately, having guaranteed nothing about the request it was meant to cover.

That is harmless ahead of a Capybara assertion such as `have_text` or `have_css`, because those retry on their own until they pass or time out. It is unsafe ahead of an assertion that does not retry — anything reading from the database — because such an assertion looks exactly once, and an instant return means it looks before the server has answered.

Three examples in `pipeline_stage_selection_spec` paired it that way. One was measured failing about one run in three.

## Waiting on the side effect instead

The reliable pattern waits for the state the action changes, rather than for the progress bar that reports it:

```ruby
before_count = Model.count
find("...").click
wait_until { Model.count == before_count + 1 }
```

A retrying page assertion placed between the action and the database read closes the same gap — waiting for a flash message that appears only once the server has answered, for instance — and several specs rely on that quite legitimately.
