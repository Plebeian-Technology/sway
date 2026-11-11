---
lat:
  mode: explanation
---

# Why the /licenses page lists what it does

`/licenses` (`app/frontend/pages/Licenses.tsx`) gives credit for the outside packages built into Sway's frontend.

Their code goes out in the JavaScript bundle every browser downloads, which counts as distributing it, so the MIT, BSD, and Apache licenses require Sway to keep their notices.

The list holds only direct dependencies whose license is not MIT — the ones whose terms differ from the permissive MIT default. Ruby gems run on the server and are never handed to users, so they are not listed. This page is public on purpose.
