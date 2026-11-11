---
lat:
  mode: explanation
---

# Why useErrorMessage joins list-shaped errors

Rails `errors.to_hash` gives each field a list of messages.

The old `.find((e) => e === swayField.name)` compared a message to the field's NAME, which could never match, so list-shaped errors showed nothing at all next to the field. Join the messages together instead.
