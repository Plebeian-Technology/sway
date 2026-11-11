---
lat:
  mode: explanation
---
# Why the credential scanner walks every tracked file

`EnvCredentialScanner` reads every tracked text file for a credential-shaped environment read that does not visibly trim whitespace, instead of checking a list of the call sites somebody once found.

An earlier sweep claimed to have trimmed all eighteen credential reads. It had not: `config/newrelic.yml` held a nineteenth, live and wired end to end from `.kamal/secrets-common` through `config/deploy.yml` to `newrelic_rpm`. The cause was the shape of the search — a grep for `ENV[` restricted to `.rb` files. A `.yml` file run through ERB when the app loads could not appear in that search, and the spec written beside it, `spec/lib/env_secret_call_sites_spec.rb`, inherited the blind spot exactly: one example per site the sweep found, so a site the sweep could not see had no example, and a missing example looked just like a clean result.

The scanner (`spec/support/env_credential_scanner.rb`) lists no call sites. It walks `git ls-files`, whatever the extension, and its `READ_PATTERNS` include the `$VAR` and `${VAR}` forms so shell scripts, compose files and Dockerfiles are seen as well. The credential set is derived from `.kamal/secrets-common`, so a newly provisioned secret comes under the check without anyone listing it. Every directory the scan skips carries its reason in `SKIPPED_PREFIXES`, and every finding allowed through carries its evidence in `EXEMPT_PATHS`, so nothing is invisible by inheritance from somebody else's filter. `spec/lib/env_secret_coverage_spec.rb` is the gate that runs it, and it also pins that the scan still reaches `.yml` and `.erb` files. `EnvReadCheck` (`lib/env_read_check.rb`) takes a stronger, parser-based approach to the same gap for one directory tree — [[settings-and-secrets#The enforcement gate]] — and the personal-detail scanner copies this architecture for the opposite class of leak, as [[personal-detail-scanner-design#Why the personal-detail scanner inverts the credential scanner's skip list]] describes.

## Why some credentials are listed by hand

`APNS_FCM_AND_TWILIO_CREDENTIALS` and `WEBAUTHN_CREDENTIALS` name credentials that `.kamal/secrets-common` does not provision, so the derived set cannot hold them and each is a deliberate addition carrying its reason.

`SWAY_DATABASE_PASSWORD` stays even though nothing reads it today: Sway runs SQLite, which takes no password. Removing it would shrink what the scan covers for a name that can plausibly come back, and its `UNDELIVERED_CREDENTIALS` entry says out loud that production is not given it. The remaining push names stay because `config/initializers/apns.rb` and `config/initializers/fcm.rb` read them straight from `ENV`, so the derived set cannot reach those reads either way: `APNS_ENV` and `FCM_PROJECT_ID` arrive via `env.clear` rather than the vault, while `APNS_SANDBOX_AUTH_KEY_P8` and `APNS_SANDBOX_KEY_ID` arrive by neither route — production holds only the production key pair, deliberately — [[apns-key-environment-pairing#Why the key pair is chosen by APNS_ENV]]. The five the vault does hold, `APPLE_TEAM_ID` and `APPLE_BUNDLE_ID` among them, are derived like any other secret and are not listed here. `APPLE_TEAM_ID` and `APPLE_BUNDLE_ID` are read through `Sway::Settings::Mobile`, whose string caster does the trimming, so no `ENV` read of either exists for the scan to find.

## Why the WebAuthn names stay listed though the scan cannot see them

`WEBAUTHN_ALLOWED_ORIGINS` and `WEBAUTHN_RP_ID` still count as credentials, but both are read through the declared `Sway::Settings::Webauthn` group, so no `ENV[...]` expression exists for the read patterns to match.

A clean scan for these two names therefore proves nothing on its own. What covers them instead is the string caster in `Sway::Settings::Base`, which strips surrounding whitespace and treats a blank as absent for every declared attribute in one place — [[settings-and-secrets#Type casters]] — proven by the `Sway::Settings::Webauthn` examples in `spec/lib/sway/settings_spec.rb`, the trailing-newline one in particular. The names stay in the scanner's hand list so `spec/config/deploy_yml_spec.rb` still checks that production is given both; it is, through `env.clear` ([[webauthn-settings-consolidation#Why production names its origins and domain in the deploy file]]).

## Why an undelivered credential is a claim rather than a silencer

`UNDELIVERED_CREDENTIALS` names the credentials the app reads that production is deliberately not given, one reason each, and `spec/config/deploy_yml_spec.rb` holds every entry to that reason in both directions.

The deploy spec fails when a credential is neither delivered by `config/deploy.yml` nor listed here, fails again when a listed name is in fact delivered, and a third time when the scanner no longer counts a listed name as one the app reads. An entry is therefore a claim that the app genuinely works without the value, not a way to quieten the check. [[settings-and-secrets#Credentials production is not given]] lists the current set.

## Why the trim check looks a few lines past the read

A call spread over several lines can put its `.strip` or `EnvSecret.` two or three lines below the read itself, so `stripped?` joins the read's line with the `CONTINUATION_WINDOW_LINES` after it before looking.

A read on one line, `&.split(",")` on the next and `&.map(&:strip)` on the third is trimmed, but a check that looked only at the read's own line would report it as untrimmed — exactly the kind of false alarm that gets a check watered down instead of the underlying bug fixed. `CONTINUATION_WINDOW_LINES` is how many lines past the read `stripped?` looks before giving up.

## Why plumbing a variable to a child process is not a read

A shell or compose line handing a variable of the same name straight to a child process — `NAME: ${NAME}`, `export NAME="${NAME}"`, `NAME=$NAME` — is passed over as plumbing rather than reported as an untrimmed read.

The value reaches the Rails process unchanged and is read there by a site the scan already covers, so a trim on the plumbing line would only hide the problem one layer earlier rather than catch it. Everything left over is use — a value dropped into a URL, a header or a `curl -u` — and is still flagged. `spec/lib/env_secret_coverage_spec.rb` pins that `compose.yml` and `scripts/dip/provision.sh` handing a credential along are not reads.

## Why an assignment is not a read

`ENV["NAME"] = value` is a write, and the scanner does not report it; the match is on a single `=` so that `ENV["NAME"] ==` stays a read.

`config/boot.rb` tidies `NEW_RELIC_LICENSE_KEY` this way. It is the one credential `newrelic_rpm` reads from `ENV` itself, ahead of `config/newrelic.yml`, so there is no call site to route through `EnvSecret`, and the write is how the value gets trimmed at all. Reporting that clean-up as an unstripped read would make the only correct handling of that variable look like the bug the scanner exists to prevent. `spec/lib/env_secret_coverage_spec.rb` pins that the write in `config/boot.rb` goes unreported while the read beside it is still seen.
