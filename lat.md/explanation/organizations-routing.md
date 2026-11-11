---
lat:
  mode: explanation
---

# Organization routes

Organization routes are declared once, with membership and position actions nested under the organization path.

## Organization routes are declared once with nested actions

[[config/routes.rb]] declares the top-level organizations resource once and nests membership, position, and position-change actions beneath it.

A duplicate standalone declaration created conflicting index, show, and create routes. The top-level update remains the admin rename action, whose locale-wide effect is documented by [[organization-position-removal#Renaming an organization changes it everywhere in its locale]].
