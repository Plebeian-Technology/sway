---
mode: explanation
summary: "Why the admin_guards lint spec fakes Pathname#read on bills_controller.rb rather than a since-deleted AdminController base class."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `admin_guards_lint_spec.rb`'s failure-path example fakes `Pathname#read`

`spec/lib/sway_admin_guard_lint_spec.rb`'s "flags a controller missing the
before_action" example fakes `Pathname#read` so one of the listed
controllers looks like it is missing the guard. The rake task calls
`Rails.root.join(path).read` on a `Pathname`, so the example intercepts
`#read` on any `Pathname` whose name ends with `bills_controller.rb`.

This used to fake an `AdminController` base class instead, but that class
was unused and has been deleted; `BillsController` is a real admin
controller already on `rake sway:lint:admin_guards`'s allowlist, so faking
its file content directly is both simpler and closer to what the rake task
actually reads.
