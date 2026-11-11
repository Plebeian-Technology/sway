---
lat:
  mode: explanation
---

# Why success flash notices are pinned across a redirect

`flashToasts.ts` turns `flash.notice` into a success toast on the client.

`ApplicationController` puts the flash on every Inertia response, so a `flash[:notice]` set before a redirect survives that redirect and reaches the page the browser lands on.

Several controllers set a specific, human-readable notice on a successful write — for example `OrganizationsController#create` sets `"Supporting/Opposing Arguments Saved"`, and `UserVotesController#create` sets `"Vote saved!"`. Each has its own request-spec example that follows the redirect and asserts the exact notice text came through, so a refactor that drops or renames the flash key fails loudly instead of silently removing the operator's confirmation toast.
