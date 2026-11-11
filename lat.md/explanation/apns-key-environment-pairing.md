---
lat:
  mode: explanation
---
# Two Apple key pairs, one per APNs environment

Apple now issues APNs auth keys restricted to a single environment, so Sway holds a production key pair and a sandbox key pair rather than one key serving both.

[[settings-and-secrets#Push notification credentials]] has the vault shape of both pairs; [[submit-the-mobile-app#Push credentials]] has how to provision them.

## Why the key pair is chosen by APNS_ENV

`config/initializers/apns.rb` and `ApnsClient` both derive their choice from the same `APNS_ENV` value, so the key presented and the host it is presented to can never disagree.

The initializer reads all four key names — `APNS_AUTH_KEY_P8`/`APNS_KEY_ID` and `APNS_SANDBOX_AUTH_KEY_P8`/`APNS_SANDBOX_KEY_ID` — unconditionally, then assigns `c.auth_key_p8`/`c.key_id` from whichever pair matches `c.env`. `ApnsClient.build_connection_pool` separately resolves `APNS_HOSTS.fetch(cfg.env, ...)` to Apple's production or sandbox host. Both choices read `cfg.env`; neither is configured on its own, so there is no third setting that could point the key at one environment while the host points at the other. An environment-restricted key presented to the wrong host comes back `403 InvalidProviderToken` — Apple's enforcement, not a check Sway runs itself. [[native-push-clients-design#Why ApnsClient keeps one connection pool per thread]] has how the connection built from that key and host is pooled.

## Why the destructive mismatch is the device token, not the key

Two mismatches hide behind `APNS_ENV`, and only one of them is cheap: a wrong key is refused, while a wrong device token is read as a dead device.

A key restricted to one environment and presented to the other host comes back `403 InvalidProviderToken`. `ApnsClient` raises `ApnsError` for any reason other than `Unregistered` or `BadDeviceToken`, `SendNativePushJob` rescues neither, so the job fails and retries and nothing but the notification is lost.

The device token is the expensive half. A build signed with a development profile registers against Apple's sandbox, so its token means nothing to the production host, which answers `400 BadDeviceToken`. `ApnsClient` maps that one to `DeviceNotRegisteredError`, `SendNativePushJob` rescues it by calling `device.revoke!` — [[device-push-token-management#Why SendNativePushJob only revokes on a real delivery receipt]] — and revocation expires every API key bound to that device in the same transaction — [[api-key-hmac-secret-handling#Why UserDevice.revoke! expires keys in the same transaction]]. A production-configured server aimed at a development build therefore signs that tester out rather than reporting a misconfiguration, which is what the sandbox pair exists to prevent.

## Why the added bundle restriction costs nothing operationally

Apple restricted both new keys to the `vote.sway.app` bundle as well as to one environment, but only the environment half required anything of Sway's code.

`ApnsClient.deliver` already sets `notification.topic` to `cfg.bundle_id` on every push, so the `apns-topic` header Apple checks a bundle-restricted key against was already correct before the restriction existed. No JWT claim changes and no second value needs to track the bundle the way `APNS_ENV` tracks the key pair, which is why bundle restriction is not a pairing problem in the way environment restriction is.
