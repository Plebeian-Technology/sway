---
mode: explanation
summary: "Why useSendPhoneVerification must notify the reader on a non-429 send failure instead of only logging it, and why that test used to encode the silent-failure bug as the expected behavior."
status: agent-extracted
related: []
---

# Why a failed phone-verification send must not stay silent

This test used to insist the failure stayed silent — "returns undefined
and says nothing" — as though that were the intended behavior. It was
not; it was the bug written down as a rule. A failed send left
PasskeyPanel sitting on the phone field with no code box and no
explanation, because writing to `console.error` tells the person nothing,
and this is the ONLY way in. The 429 case above still has its own message
and returns before reaching here, so nobody gets two messages.
