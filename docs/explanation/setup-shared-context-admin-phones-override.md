---
mode: explanation
summary: "Why the Setup shared context's #setup swaps User::ADMIN_PHONES/API_USER_PHONES with the Array form rather than a bare phone string, and where the swap gets restored."
status: agent-extracted
related: [admin-gate-shared-examples]
---

# Why `Setup#setup` swaps `ADMIN_PHONES`/`API_USER_PHONES` as an Array

`spec/support/setup.rb`'s `#setup` replaces `User::ADMIN_PHONES` and
`User::API_USER_PHONES` with `[u.phone]` — an Array containing the created
user's phone — rather than the bare phone string. `ADMIN_PHONES` is
normally an Array everywhere else in the app, and `Array#include?` and
`String#include?` disagree in meaning: one checks for an equal ELEMENT,
the other checks for a matching SUBSTRING. A bare phone string swapped in
here would have silently changed what "admin" means to check — a
substring match instead of an exact one — everywhere `verify_is_sway_admin`
consults the constant during the example. The Array form matches every
other `ADMIN_PHONES`/`API_USER_PHONES` call site in the suite (see also
`docs/reference/admin-gate-shared-examples.md` for the sibling
`:sway_admin` factory trait, which does the same kind of swap through a
different mechanism).

The constant is restored after every example by the global
`config.around` in `rails_helper.rb` — not by `#setup` itself,
which never restores its own override.
