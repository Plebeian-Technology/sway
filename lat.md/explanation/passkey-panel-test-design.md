---
lat:
  mode: explanation
---

# PasskeyPanel test design notes

Bug histories behind PasskeyPanel.test.tsx's examples: the throttle latch that never expired, the code input's controlled-value binding, and the panel's silent failure on an unhandled sign-in error.

## Why the throttle latch has to expire

The panel's "you are being rate limited" state has to expire.

When the server answers 429 (too many requests), the three auth hooks hand the panel a real future time, read from the Retry-After header. The old check only asked whether that time was set, never whether it had passed, so one rate limit disabled the only sign-in panel until the person reloaded the page by hand. The submit button must switch back on once that time arrives.

## Why the code-input binding check is deliberately weak

React must own the value of the one-time-code input (`value={code}`), so that pressing Cancel and starting over clears the old text.

Only the code input is written as `value={code}` — the phone input binds a reworked value — so matching that text pins this one input and no other. A weak check on purpose: the binding itself is the whole point.

## Why an unhandled sign-in error can't fail silently

This panel is the ONLY way to sign in.

`startAuthentication` deals with a 429 (too many requests) itself and throws everything else back to the panel. The panel's catch handled 422 and dropped the rest on the floor: the spinner flashed, nothing appeared, and the person had no way to tell a server crash from a slow connection.

## Why the 422 SMS-fallback case must stay silent

`useWebAuthnAuthentication` already owns the 429 case: it pops the rate-limit message and returns instead of throwing.

A 422 means "no passkey for this phone, fall back to an SMS code", which is a normal path, not a failure. Neither may pick up a second message that contradicts the first.
