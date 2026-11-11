---
lat:
  mode: explanation
---

# Why the VCR credential filter is derived, not hand-written

`VcrCredentialFilter` (`spec/support/vcr_credential_filter.rb`) registers one VCR recording filter per credential the project sets up, worked out from `.kamal/secrets-common` rather than listed by hand.

`spec/support/vcr.rb` used to name two credentials by hand, and both were dead: `LEGISTAR_API_KEY` (Legistar's Web API needs no credential) and `LEGISLATION_SERVICE_BEARER` (a Python service since deleted). The recording rules protected nothing, and not one of the credentials they could have protected was named. A hand-written list fails exactly this way: it cannot be wrong in a way anyone notices, because a filter for a variable nothing sets looks the same as no filter.

So the list comes from `EnvCredentialScanner#credential_names`, which reads `.kamal/secrets-common`. Adding a new secret there brings it under the filter with nobody having to remember.

## Why this is not hypothetical

Re-recording a cassette with `record.

Re-recording a cassette with `record: :all` under `VCR=record` calls the live upstreams, and two of them put the key right in the request URL as a query parameter: OpenStates (`apikey=`, called from `sway_registration_service.rb` and `maryland_refresh.rb`) and congress.gov (`api_key=`, called from `congress_refresh.rb`). Without a live filter for the credential in play, that key lands in the recorded cassette verbatim.

## Why a text-scan test, not a behavior test, catches a dead filter

A filter for a variable nothing sets looks exactly like no filter to any behavior-based check — both leave the recording clean, because neither credential's value ever appears in the traffic to begin with.

That is how `LEGISTAR_API_KEY` and `LEGISLATION_SERVICE_BEARER` sat in `spec/support/vcr.rb` unnoticed through a whole cleanup sweep.

The spec that guards against this reads `spec/support/vcr.rb` as text instead: every `filter_sensitive_data("<NAME>")` placeholder still hand-written there must name a credential `EnvCredentialScanner#credential_names` actually returns. Comment lines are skipped so the file can explain why the dead pair was removed without the explanation tripping its own check. A name that fails this either names a dead credential (delete the filter) or a real one missing from `.kamal/secrets-common` (a deploy bug worth more than a cassette filter).

## Why the Google Maps key filter stays alongside the derived set

`spec/support/vcr.rb` keeps one hand-written filter.

`spec/support/vcr.rb` keeps one hand-written filter, `config.filter_sensitive_data("<GOOGLE_MAPS_API_KEY>")`, matching the key's SHAPE (`/AIza[A-Za-z0-9_-]{35}/`) inside the recorded request URI, rather than dropping it once the derived set was in place. It promises something DIFFERENT from the derived filters: it blanks out a Google key already sitting in a recording even in a process where `GOOGLE_MAPS_API_KEY` itself is unset, because it matches on the key's appearance rather than on the current environment. The derived filter covers the case this one cannot — a key that IS in the environment but not in the URL, because it was sent as a header instead, for example. The two are complementary, not redundant.

## Why redactable_value returns nil, not an empty string, for nothing to blank out

`VCR::HTTPInteraction#filter!` does nothing with an empty string — `nil` and `""` both have no effect on it.

`redactable_value` returns `nil` specifically, rather than `""`, because `nil` says plainly "there is no replacement to make," which is the true state (the variable is unset, or too short to safely redact), where an empty string would misleadingly suggest a value was found and is simply blank.

## Why the redaction length floor is 12

VCR hides a recorded secret with a plain text search-and-replace (`VCR::HTTPInteraction#filter!`), and the replacement runs BOTH ways — `before_playback` puts the real value back.

So a value short enough to turn up as ordinary text would damage a recording rather than protect it, and would do it quietly, on playback, in a fixture that specs match on by `body`.

`MINIMUM_REDACTABLE_CHARS` is 12, because that is the length of the shortest value in the derived set that can actually reach a recording: `TWILIO_FROM_PHONE`, `"+1"` plus ten digits.

What that leaves out today is the three `APNS_*` identifiers: `APNS_ENV`, which is literally the word "production" or "development", and `APNS_KEY_ID` and `APPLE_TEAM_ID`, both ten characters. None of them can appear in a recording in the first place: apnotic sends over `NetHttp2::Client` (apnotic-1.8.0 `connection.rb`, line 40), which WebMock does not intercept, so VCR never sees APNs traffic.

The clash the length floor prevents is a real kind of problem that, measured, has not happened yet: the one recording in `spec/cassettes` contains "Refer to Housing and Community Development" twice, out of Legistar matter history, but VCR's replacement is case-sensitive and the `APNS_ENV` values are lowercase, so the case-sensitive count for each is 0. One capital letter, in a collection of one recording.

## Why the spec runs VCR's real before_record hook chain instead of a stand-in

`spec/config/vcr_credential_filter_spec.rb#scrubbed_cassette_text` builds a real `VCR::HTTPInteraction` and runs it through `VCR.configuration.invoke_hook(:before_record, interaction.hook_aware, cassette)`.

`spec/config/vcr_credential_filter_spec.rb#scrubbed_cassette_text` builds a real `VCR::HTTPInteraction` and runs it through `VCR.configuration.invoke_hook(:before_record, interaction.hook_aware, cassette)` — the exact call `VCR::Cassette` makes on the way to disk — over an interaction carrying the probe text in every spot a credential can land: the request URL (spelled both ways the upstreams spell it), the request body and headers, and the response headers and body.

Going through the real hook chain instead of a stand-in filter call is the whole point: a filter that is registered but never actually invoked would sail past a mock that calls the filter directly, and then fail in production — which is the very bug this spec exists to guard against. Some of VCR's own built-in hooks (`preserve_exact_body_bytes` and similar) only run for certain cassette tags, and their filter lambda calls `cassette.tags`, so the spec passes a stand-in `VCR::Cassette` double with an empty tag list — the smallest object that lets the whole real chain run, which is what makes this a test of the real pipeline rather than of Sway's own filters in isolation.
