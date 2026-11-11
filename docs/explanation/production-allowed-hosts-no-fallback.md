---
mode: explanation
summary: "Why config/environments/production.rb has no fallback for RAILS_ALLOWED_HOSTS and reads it from deploy config instead of hardcoding it."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why there is no fallback for `RAILS_ALLOWED_HOSTS`

Which names and addresses the production machine will answer to is NOT
written in `config/environments/production.rb`: the list holds
deployment-specific addresses, which do not belong in the repository. `config/deploy.yml` passes
it in from `deploy/config/sway.env`.

There is no fallback on purpose. A guessed list is the kind of mistake that
looks like a working deploy until somebody reaches the site by an address
nobody thought of, and then every request is refused before it reaches any
code that could explain why.
