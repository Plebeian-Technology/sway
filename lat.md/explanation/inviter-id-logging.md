---
lat:
  mode: explanation
---

# Inviter identifier logging

The invitation cookie is useful for attribution, but its value identifies a person and should not appear in logs.

## Lookup logs presence only

[[app/controllers/application_controller.rb#ApplicationController#invited_by_id]] records whether the permanent inviter cookie exists, not its value. The cookie key is not covered by the logger's sensitive-key filter, so logging the identifier itself would disclose it.
