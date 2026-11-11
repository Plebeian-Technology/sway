---
lat:
  mode: explanation
---

# OrganizationFollowControl: two regression guards

Two tests guard against past bugs.

The "member with no follow row" test really clicks the Preferences button and checks the picker opens, because an old condition on followId used to swallow that click. And the first-follow Save test checks it aims at the org follows route, never /0/preferences.
