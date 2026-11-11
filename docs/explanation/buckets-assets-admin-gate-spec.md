---
mode: explanation
summary: "Why the Buckets::AssetsController admin-gate spec accepts an error past the admin check as proof of the gate, since the test environment has no Google Cloud Storage credentials."
status: agent-extracted
related: []
---

# Why `Buckets::AssetsController`'s admin-gate spec tolerates a downstream error

`spec/requests/buckets/assets_spec.rb` proves that `Buckets::AssetsController`
is admin-only: the controller runs `before_action :verify_is_sway_admin` for
every action, not just some, so `POST /buckets/assets` needs an admin.

The example that signs in as an admin still errors out, because the test
environment has no Google Cloud Storage credentials. That is fine: the admin
check has already passed by the time the GCS call fails, and the only claim
this spec makes is "not forbidden" — not that the upload itself succeeds.
