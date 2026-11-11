---
lat:
  mode: explanation
---

# Why mobile's phone formatter is tested against the web copy

The phone formatter in `mobile/src/utils/phone.ts` has to behave exactly like the web one (`app/frontend/sway_utils/phone.ts`).

`mobile/__tests__/utils/phone.test.ts` pins the formatting and validation rules so the two copies do not drift apart.
