---
lat:
  mode: explanation
---
# Settings groups

Each settings group under `lib/sway/settings/` is an `Anyway::Config` subclass that names its own environment prefix and config name. [[settings-and-secrets#Settings groups]] lists the groups; this page holds the reasoning behind how a group is declared.

## Why some groups declare a blank env prefix

`DevLogin`, `Legislation`, `Llm`, `Mobile`, `Ops` and `Upstream` declare `env_prefix ""` because their attribute names share no common word for a prefix to bind to.

`DevLogin` holds the phone-check-skip switch beside the stand-in account values
the provisioner builds an account from when that switch is on. `Ops` holds the
inbound-text forwarding address, the deploy stamp, the backup-skip switch, the
in-container flag, the dev tunnel host and the monitoring dashboard's address
and audience. `Upstream` holds seven upstream base
URLs. `Mobile` holds the download page's store link, the two build numbers the
launch endpoint reports, the fingerprint list the Android app-link file
publishes, the Apple team and bundle ids and the hosts that serve the
association files.

`Legislation` and `Llm` are the near misses. Seven of `Legislation`'s eight
names already carry `LEGISLATION_` inside the attribute name itself, but the
eighth, the tesseract data directory, shares nothing with them, and a prefix
only seven of eight names carry cannot be declared. `Llm` reads two unrelated
families of names, `LLM_` and `LLAMACPP_`, and no single prefix covers both.

In every case each attribute reads its own bare environment variable name in
upper case, with no lookup table between a call site and the variable it names.

Leaving the prefix undeclared is the alternative, and it does not leave the
name bare: anyway_config 2.8.1 derives a prefix from the group's own config
name, so `Ops` would read `OPS_SWAY_DEPLOYED_AT` and never `SWAY_DEPLOYED_AT`, with
nothing reporting the mismatch — the real variable simply reads as unset. That
is why every group names both `env_prefix` and `config_name` itself.

## Why the webauthn group binds one shared prefix

`Webauthn` declares `env_prefix "WEBAUTHN"` because all of its attributes are facets of one relying party: which origins may complete a passkey ceremony, the domain a passkey is tied to, and which hosts announce the related origins.

`RateLimits` is the only other group whose attribute names all carry one shared
word, and it binds `RATE_LIMIT` for the same reason. A prefix binds where the names
describe facets of a single underlying thing, not where unrelated settings
happen to share a file.

Each of the two webauthn names had more than one reader before the group
existed, each reading the environment raw and each holding its own production
fallback, and those fallbacks disagreed about how many origins production
allows. Both readers now take the one declaration, so the accepted set cannot
differ between the boot-time initializer and the request path.

## Why rp id has no default

`rp_id` is declared with no default and is not `required`: `nil` is a legitimate value outside production, because each of the two readers supplies its own fallback rather than sharing one.

Production has no fallback; a production boot without the value stops
([[webauthn-settings-consolidation#Why production names its origins and domain in the deploy file]]).
Outside production the two readers differ deliberately. The relying-party concern answers a real request and names
the host the phone actually reached, which is what lets a phone on the tunnel
address sign in. The initializer runs at boot with no request in hand and
leaves the value `nil` for the library to derive from the first allowed origin.

A default declared in the group would collapse both readers onto one fallback,
and the one it collapsed them onto could not be the host of a request nobody
has made yet, so the tunnel case would break.

## Why the mobile group's id and version numbers are text

`apple_app_store_id`, `mobile_min_version` and `mobile_latest_version` are declared `:string` because each would become a number under type guessing, and none of the three is one.

A ten-digit App Store id reads as an Integer to anything that guesses a type,
and the placeholder it defaults to, `<APPLE_APP_ID>`, is not a number at all:
the download page drops the store link while the value still carries the
placeholder's angle brackets, until the real id exists in App Store Connect
([[submit-the-mobile-app#Values no waiver covers]]). A version written with
one dot reads as a Float, which drops a trailing zero so `1.10` becomes `1.1`,
and a bare digit reads as an Integer with no dots left in it. The mobile
client takes both versions as text and splits them on their dots to compare
them part by part, so a misread version is a different version by the time
it reaches a phone.

`Base` already turns the gem's automatic casting off for every group, so the
declared `:string` is not what stops the guess. It routes the value through
the group's own string caster, which strips it and reads blank as `nil` so
the default can take over, and it records on the declaration that the shape
is deliberate: a value that looks like a number here is not one.

## Why the fingerprint list is compacted on load

The array caster leaves a `nil` in `android_cert_sha256_fingerprints` for an empty entry between two commas or a whitespace-only value, so the group compacts the list once it is built.

The per-element string caster reads blank text as `nil`, and the gem's comma
split keeps that slot rather than dropping it, so a stray comma in the
environment value would carry a `nil` into the list the Android app-link file
publishes. The compact is the `reject(&:empty?)` the old direct `ENV` read
did, moved into an `on_load` callback so it runs once, on the built array,
instead of at every call site. `Webauthn#allowed_origins`, `Webauthn#related_hosts` and
`Mobile#app_association_hosts` have the same gap for the same reason and
repair it the same way.

## Why the freeze runs after a group's own repair

`Base` never calls `freeze_mutable_attributes!` itself; a group with its own `on_load` repair (`Mobile`, `Webauthn`) appends the freeze as its last callback, after that repair.

A String or Array attribute reader otherwise hands out the same mutable
object on every call:
`Sway::Settings.webauthn.allowed_origins` would return the identical, unfrozen
Array each time. That array reaches `WebAuthn::RelyingParty.new` and the
Android app-link file, so one caller mutating it would corrupt every other
caller's view of a security boundary.

The freeze reassigns each String or Array attribute to its frozen self, and
load callbacks run in the order they were appended, a subclass's after its
parent's. A callback that reassigns an attribute after the freeze —
`self.foo = foo.compact` — hands back a fresh, unfrozen object and undoes it.
That is why the compact comes first and the freeze second in both groups, and
why `Base` leaves the call to the group instead of adding it to the shared
callbacks, where it would run before any repair a subclass appends.

## Why the base class replaces the gem's casters

`Base` registers its own `:string`, `:integer`, `:float` and `:boolean` casters on the default type registry, because the gem's own casters answer zero or `false` for text they cannot read.

A setting whose value is unreadable is better stopping the boot under its own
name than becoming `0` quietly: the gem's plain `:integer` is `to_i`, which
reads `"lots"` as zero, and its `:string` is `to_s`. Both the plain and the
strict spelling of a number caster resolve to one block here, because the gem
ships `:integer!` but no `:float!`, and its RBS generator recognises only the
plain names, so a strict spelling generates no usable type.

Base 10 is passed explicitly because bare `Integer()` honours Ruby's literal
prefixes: a leading zero reads as octal, so `"030"` becomes `24` and `"090"`
raises outright. That is the same silently-different-number failure the strict
caster exists to remove, with a different wrong number. `Float()` has the
matching hole for a leading `0x`, where `"0x10"` becomes `16.0`, so the text is
matched against a plain decimal format before `Float()` ever sees it.

Blank is the one case the boolean caster answers `nil` rather than `false`. The
gem answers `false`, which reads an absent value as a switch turned off and
hides the declared default of on. Unrecognized non-blank text stays lenient and
reads as `false`, because the registry is process-wide: a raise here would also
raise for the backup-skip switch, the phone-check-skip switch and the llama.cpp
thinking switch, where an unreadable value belongs on the safe side.
`RateLimits` wants the opposite answer for its ten switches and gets it by
reading its own raw environment value, rather than by widening the shared
caster.

The registry is `Anyway::TypeRegistry.default`, which is global to the process.
Nothing else in this application uses it, so the reach is contained, though the
registration line itself does not show that.

## Why the required check moves to the end of the callbacks

`Base` removes the gem's required-attribute check from the front of the load callbacks and appends it again after the blank repair, so a blank value falls back to its default before the check runs.

The gem registers that check on `Anyway::Config` itself, which makes it the
first entry every subclass inherits, and a group's own `on_load` repair lands
after it. Left where it was, it raised for a required attribute that has a
default whenever the environment supplied a blank value — the very case the
repair exists to answer, judged before the repair had run.

## Why the generated RBS interface is renamed per group

`Base.to_rbs` renames the interface the gem generates from `_Config` to one name per class, so every group's committed signature can sit in the `Sway::Settings` namespace at once.

The gem's generator names a namespaced class's interface `_Config` every time,
which is fine for one group and a duplicated declaration for the second: two
files under `sig/lib/sway/settings/` would each open `module Sway::Settings`
and each declare `interface _Config`, and RBS refuses the pair. The rename
gives each class its own `_<ClassName>Config`.

The signature spec regenerates through this same overridden method and compares
the result against the committed text, so a committed file stays a verbatim
regeneration rather than a hand-edited copy of one.

## Why the frontend's IS_PRODUCTION reads the build, not the hostname

`app/frontend/sway_constants/index.ts`'s `IS_PRODUCTION` is decided by how the app was built, not the URL in the address bar.

A development build stays a development build whatever hostname serves it, so
a contributor running their own Cloudflare tunnel (`DEV_TUNNEL_HOST`) is not
mistaken for production — which would otherwise send local errors to Sentry and
switch off `logDev`.

