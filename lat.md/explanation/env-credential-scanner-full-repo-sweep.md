---
lat:
  mode: explanation
---

# Why EnvCredentialScanner is a scanner, not a list of examples

`EnvCredentialScanner` (`spec/support/env_credential_scanner.rb`) scans the repository for reads of credential-shaped environment variables that do not visibly trim whitespace.

An earlier change claimed to have trimmed "all 18 credential ENV reads". It had not: `config/newrelic.yml` held a nineteenth, live and wired up end to end (`.kamal/secrets-common:31,42` + `config/deploy.yml:136` + `newrelic_rpm` 10.6.0). The cause was not carelessness — it was the shape of the search that limited the sweep:

```
grep -rn 'ENV\[' --include='*.rb'
```

A `.yml` file run through ERB when the app loads could not possibly show up in that search, and the test shipped alongside it (`spec/lib/env_secret_call_sites_spec.rb`) inherited the blind spot exactly: it has one example per call site the sweep FOUND, so a site the sweep could not see has no example, and a missing example looks just like a clean result.

## What this scanner does instead

It does not list call sites.

It scans every tracked text file, whatever its extension. Adding a secret to `.kamal/secrets-common` brings it under this check automatically; putting a credential in a `.yml`, an `.erb`, a Dockerfile, or a shell script does not get it out.

`EnvReadCheck` (`lib/env_read_check.rb`) takes a different, stronger approach to the same underlying gap for one directory tree — see `docs/explanation/env-read-check-design.md`.

## Why an ENV assignment does not count as a read

`ENV["NAME"] = value` is a write, not a read, and the scanner does not report it.

`config/boot.rb` cleans up `NEW_RELIC_LICENSE_KEY` this way — it is the one credential `newrelic_rpm` reads from `ENV` itself, ahead of the yaml file, so there is no call site to route through `EnvSecret`. Reporting that clean-up as an unstripped read would make the only correct handling of that variable look like the bug it exists to prevent.

A shell or compose line handing a variable of the SAME name straight to a child process — `NAME: ${NAME...}`, `export NAME="${NAME...}"`, `NAME=$NAME` — is treated the same way: as plumbing, not use. The value reaches the Rails process unchanged and is read there by a site the scan already covers, so trimming a check onto the plumbing line itself would only hide the problem one layer earlier rather than catch it. Everything left over IS use — a value dropped into a URL, a header, or a `curl -u` — and is still flagged.

## Why SWAY_DATABASE_PASSWORD and the WebAuthn names stay listed by hand

`APNS_FCM_AND_TWILIO_CREDENTIALS` and `WEBAUTHN_CREDENTIALS` list credentials that do NOT come from `.kamal/secrets-common`, so `#provisioned` cannot find them.

`APNS_FCM_AND_TWILIO_CREDENTIALS` and `WEBAUTHN_CREDENTIALS` list credentials that do NOT come from `.kamal/secrets-common`, so `#provisioned` cannot find them — they are listed by hand, so adding one is a deliberate choice, each with a reason.

`SWAY_DATABASE_PASSWORD` stays even though nothing reads it today: Sway runs SQLite, which takes no password. Removing it would shrink what this scan covers for a name that can plausibly come back.

`WEBAUTHN_ALLOWED_ORIGINS` and `WEBAUTHN_RP_ID` stay listed as credentials, but the scanner can no longer SEE either one move: both are now a declared setting (`Sway::Settings::Webauthn`) with no `ENV[...]`/ `EnvSecret.read` expression anywhere for `READ_PATTERNS` to match — so a clean scan of these two names now means nothing on its own. What covers them instead: `Sway::Settings::Base`'s `:string` caster strips surrounding whitespace and treats blank as absent for every declared attribute, in one place, proven by `spec/lib/sway/settings_spec.rb`'s "Sway::Settings::Webauthn" examples (the trailing-newline one in particular).

## Why UNDELIVERED_CREDENTIALS entries are claims, not a way to silence the check

`UNDELIVERED_CREDENTIALS` lists credentials the app reads that production is deliberately NOT given.

`UNDELIVERED_CREDENTIALS` lists credentials the app reads that production is deliberately NOT given, each with the reason, and is read by `spec/config/deploy_yml_spec.rb`, which fails when a credential is neither delivered nor listed here — and fails again if an entry goes stale in either direction. Each entry is a claim that the app genuinely works without the value; it is not a way to quieten the check. The delivery gap an entry records is real, and some of these groups have issues open against them (native push configuration, for instance).

## Why the trim check looks a few lines past the read

When a call is spread over several lines, the `.strip`/`EnvSecret.` call can sit two or three lines below the actual read:

```ruby
ENV["WEBAUTHN_ALLOWED_ORIGINS"]
  &.split(",")
  &.map(&:strip)
```

Checking only the one line the read itself is on would report that site as untrimmed — exactly the kind of false alarm that gets a check watered down instead of the underlying bug fixed. `CONTINUATION_WINDOW_LINES` (3) is how many lines past the read `#stripped?` looks before giving up.
