---
mode: explanation
summary: "Design notes for OrganizationsController: why #show 404s explicitly, the errors payload shape in #create, icon_url provenance rules, the all-or-nothing save transaction, and the #update rename scope."
status: agent-extracted
related: [docs/explanation/organizations-routes-consolidation.md, docs/explanation/mirrored-asset-query-cost-coverage.md]
---

<!-- vale Vale.Spelling = NO -->

# `OrganizationsController` design notes

## Why `#show` renders a real 404 instead of `{ success: false }`

A missing organization answers with a real 404 in the app's standard error
shape. Answering 200 with `{ success: false }` would look like success to
any HTTP client that checks only the status code.

`#show` uses `find_by` rather than `find` in `set_organization`, so a
missing id yields `nil` and `#show` can answer "Organization not found."
instead of raising. Two routes reach it: `GET /organizations/:id` and the
mobile API's `GET /api/organizations/:id`. The web page a person visits is
a different controller, at `/public/organizations/:id`. `#show` returns
the organization's name, icon, and bill positions as JSON — never its
members.

## Why the `#create` errors payload key is plural

The errors hash key has to be `:organizations`, plural. The save loop
writes to `errors[:organizations][index]`, and the React panel reads
`errors.organizations`. A singular key matches neither side, and field
errors then disappear without a trace.

Inside that loop, position-save errors are read via `.errors.objects`, not
a `|attribute, message|` pair — each item is one `ActiveModel::Error`
object, not a two-element pair. Destructuring it as a pair would bind the
whole object to the first name and `nil` to the second, and the error
payload would come back empty.

## Why icon URL provenance rules exist

`icon_url` records where a picture CAME FROM, and an upload has no outside
source. Neither does an address the form hands back that already points at
our own storage: the Bill Creator seeds its fields from the props the page
was built with, so an organization that already has an icon submits the
address `MirroredAssetUrl` worked out, rather than anything a person typed.
Storing either would write this machine's name into the database for
good, and a later change of domain would leave the row pointing at
nothing — the same harm undone in the mirroring service.

`our_own_asset_url?` decides this by matching on the URL PATH rather than
the host, which is what makes it work in development, where our own
address is on localhost and not a `sway.vote` name — the exact case that
put a developer's machine name into production rows. A blank address
counts as ours: there is nothing outside to record.

`Organization#to_public_json` and `#to_simple_builder`/`#to_builder` all
read `#mirrored_icon_url` rather than the raw `icon_url` column, for the
same provenance reason: both give our own copy of the icon when Sway holds
one, and the original outside address when it does not — the same answer
either builder gives. Reading the raw column in any of these was the only
reason an admin upload ever had to write Sway's own address back into
`icon_url` in the first place. `Organization#to_simple_builder` is the one
seam every organization icon renders through on every screen, web and
phone — the same one-key/one-behavior pattern
`Legislator#photo_url` follows for portraits (see
[legislator-resource-design.md](legislator-resource-design.md)).

## What PUBLIC_FIELDS is, and the rule around it

`Organization::PUBLIC_FIELDS` is the explicit allow-list of fields the
non-admin `Public::OrganizationsController` may expose. The record's raw
`as_json` must NEVER be called from a public surface — callers always go
through `#to_public_json`, which reads only from this list. The regression
that would catch a future violation is
`spec/models/organization_public_json_spec.rb`. `:follower_count` is
included in the list (backed by `#follower_count`, not a real column) so
web and mobile org pages can render it without a separate lookup.

## Why `#create` rolls the whole batch back on any failure

All or nothing: one organization or position failing to save undoes every
save in the same request, so what is stored always matches the error
response the client gets. An icon attached during a save that then rolls
back can leave an unused file behind — that is accepted, since it gets
cleaned up later and only happens when a save has already failed.

## Why `#update` only ever renames

`#update` accepts the name and nothing else — `organization_update_params`
permits only `:name`. Leaving out `sway_locale_id` and `icon_url` means a
rename cannot move the organization to another locale or wipe its icon.

A name is unique within a locale and shared by every bill in that locale,
so a rename changes it EVERYWHERE in that locale. After saving, it
redirects back to the tab the admin renamed from — the same tab lookup
`#create` uses — so the panel shows the new name without a refresh. The
`bill_id` param only builds that redirect target; the rename itself
affects no single bill.

## What production_organization_icon_sources_spec.rb checks

`spec/production_readiness/production_organization_icon_sources_spec.rb`
checks the provenance rule above against real production data,
after the whole migration chain has run — because a data migration reports
what it did through `say`, which goes into the deploy log and is read by
nobody. It asserts no `Organization#icon_url` ever points back at Sway's
own `/rails/active_storage/` address, for the same reason described above:
an address pointing at our own storage names the machine that generated
it, so it survives a change of domain as a link to nothing.
