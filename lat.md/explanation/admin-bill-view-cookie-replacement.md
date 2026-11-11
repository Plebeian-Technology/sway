---
lat:
  mode: explanation
---

# Why AdminBillView is a row, not a cookie

`AdminBillView` records on the server when an admin last opened a bill's edit page. It drives the pop-up notice in the Bill Creator that says the page has newer data than what the admin is looking at.

It replaces a per-bill `last_viewed_bill_<id>` cookie. A busy admin who opened enough bills pushed that scheme past the browser's roughly 4KB limit on total cookie storage, silently losing the oldest "last viewed" entries once the limit was hit. A database row, keyed on `(admin_user_id, bill_id)`, has no such ceiling.
