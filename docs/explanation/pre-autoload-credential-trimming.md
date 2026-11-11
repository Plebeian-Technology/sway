---
mode: explanation
summary: "Why several boot-time initializers trim credential env vars by hand instead of through EnvSecret, and what a stray newline breaks in each one (APNs, FCM, Geocoder, Sentry)."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why credential env vars get trimmed inline before autoload

Several boot-time initializers read a credential straight from `ENV` and
strip it by hand (`.to_s.strip.presence`) instead of going through the
`EnvSecret` helper. In each case the trimming happens right there instead of
through `EnvSecret` because the initializer runs before Rails' autoloader
can find that class; `.presence` copies what `EnvSecret.read` does.

## APNs (`config/initializers/apns.rb`)

`APNS_KEY_ID` goes into the `kid` field of the signed token sent to Apple,
and Apple compares it character for character — a stray newline gets a 403
`InvalidProviderToken` back. The `.p8` key is PEM text, where surrounding
whitespace means nothing, so trimming it is safe and stops `enabled?`
treating a lone newline as a real credential.

The remaining three values need the same trimming, and are all required. A
default value cannot save them: `ENV.fetch(name, default)` hands back
whatever is there whenever the variable is SET, so it covers a missing value
but not `"production\n"`.

- `team_id` goes into the `iss` field of the signed token, compared
  character for character by Apple -> 403 `InvalidProviderToken`.
- `bundle_id` goes into the `apns-topic` header, also compared exactly ->
  400 `BadTopic`.
- `env` is the worst. `APNS_HOSTS.fetch(c.env, HOSTS["development"])` does
  not recognize `"production\n"`, so real pushes go to Apple's TEST server
  instead, every device token comes back `BadDeviceToken`, and
  `SendNativePushJob` calls `device.revoke!` — which drops the device and
  expires every API key tied to it. One newline signs every iOS user out.

## FCM (`config/initializers/fcm.rb`)

`project_id` is pasted straight into the FCM URL, so a stray newline at the
end makes a broken URL rather than a clear "bad credentials" error. The
service-account value is JSON, where surrounding whitespace means nothing.

Missing credentials do not stop the app from starting: `FcmClient.send`
checks `enabled?` before doing anything, so dev and test machines with no
FCM credentials quietly skip sending instead of blowing up at boot.

## Geocoder (`config/initializers/geocoder.rb`)

The key is sent as a URL parameter on every lookup. A stray newline at the
end of the value gets URL-encoded and tacked onto the key, Google replies
`REQUEST_DENIED`, and registration reports it as an address it could not
locate.

## Sentry (`config/initializers/sentry.rb`)

Sentry parses the DSN as a URL. A stray trailing newline in the env var
breaks that parse and Sentry quietly turns itself off — the only symptom is
that error reports stop arriving.
