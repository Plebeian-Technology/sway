---
mode: explanation
summary: "Why EnvSecret.read strips a trailing newline and returns nil rather than an empty string for a blank or unset credential."
status: agent-extracted
related: [api-key-hmac-secret-handling, env-credential-scanner-full-repo-sweep]
---

<!-- vale Vale.Spelling = NO -->

# Why `EnvSecret.read` strips and returns nil, not blank

A trailing newline is the ORDINARY result of `kamal env push` reading a
file, or of `KEY=$(cat key.txt)`. It survives every step and ends up going
out over the network.

## The two failure modes are not equally noisy

- An API-key secret with a stray newline comes back as a 401 that looks
  exactly like a revoked key (confirmed by trying it against Anthropic).
  Recoverable, but the operator cannot work out why from the error alone.
- A signing secret with a stray newline does NOT fail. It quietly changes
  every signature the app computes and checks. Both sides agree, so
  everything looks fine until the day the secret is read without the
  newline — at which point every key issued before stops verifying all at
  once, with no error naming the cause.

That asymmetry is why `EnvSecret.read` strips every credential the same
way rather than leaving each call site to notice on its own.

## Why nil instead of ""

`.to_s.strip` on its own would turn an UNSET variable into `""`, which
slips past a `nil?` check and hands an empty secret to `OpenSSL::HMAC` —
the same silent wrong-signature bug, this time caused by the fix.
`.presence` is what keeps the loud failures at call sites working: a blank
or unset variable comes back `nil`, so a `nil?` guard still fires.

## Why `EnvSecret.fetch!` raises instead of returning nil

`fetch!` is the version for callers that relied on a bare `ENV.fetch(name)`
raising `KeyError`. A blank value raises too, since `""` or `"\n"` is a
`kamal env push` mistake, not a credential — treating it as a real value
would just reintroduce the blank-secret bug `.presence` exists to prevent,
one level up. The raised message names the variable and never echoes its
value.

## Why a credential is read once and reused, not read again at the point of use

`SwayRegistrationService#find_legislators_from_open_states_geo_endpoint`
reads `OPEN_STATES_API_KEY` once into a local and reuses that local for
both the blank check and the request. A guard and a use that each read the
`ENV` separately can disagree — the exact bug once found in
`ClaudeAdapter#api_key`: the guard sees one value and the use
sees another if anything changes between the two reads. Reading once makes
the value that passes the blank check provably the same value sent to the
API.
