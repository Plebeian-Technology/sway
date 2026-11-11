---
lat:
  mode: explanation
---

# Why some system specs scope assertions to the app element

`/public/organizations` used to come up BLANK in a real browser.

`Public::OrganizationsController` asked for a page named "Organizations", but `app/frontend/pages/Organizations.tsx` did not exist, so the code that loads page components threw and React mounted nothing. A 200 from the server only proves the outer HTML shell came back, and Capybara's `have_text` can even match the JSON blob Inertia embeds in that shell — which is exactly how a blank page went unnoticed. The missing pages were then built.

The fix carried into how these specs assert: they check only the text React rendered inside `#app` (`find_by_id("app", wait: 10)`), not the whole document. Nothing can pass by matching the embedded JSON prop payload; only a real render counts. `spec/system/public_organizations_spec.rb`, `spec/system/bill_org_positions_spec.rb`, `spec/system/bills_search_sort_spec.rb`, and `spec/system/organization_follows_spec.rb` all follow this convention.
