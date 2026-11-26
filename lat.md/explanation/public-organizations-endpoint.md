---
lat:
  mode: explanation
---
# The public organizations endpoint

`Public::OrganizationsController` serves read-only organization browsing to everyone, signed in or not. It is a separate controller from the admin one so that the admin gate and the public reads cannot drift into the same class.

`OrganizationsController` keeps its admin gate on `#create`. This controller
answers four shapes: every active organization, the organizations of one
locale, the ones the signed-in reader follows, and one organization with its
bill positions.

## What a signed-out reader is never sent

Follow state and membership state ride on the payload only when
`current_user` is present.

The index adds a map of the reader's own follows and the ids of the
organizations they belong to; the show adds the reader's own follow id and the
same membership ids. Both read through `current_user`, so the widest thing
either can disclose is the requesting reader's own relationships. A signed-out
request gets the payload the endpoint has always returned.

No payload carries a follower count
([[organization-follower-set-queries#Organization's follower-set queries#No public follower count]]).

## Why the list preloads icons and the detail does not

Resolving an organization's icon reads the attachment row and then the blob
row, so the question is whether saying that up front costs less than asking per
record.

On the index it does, because every returned row resolves an icon. On the show
it does not, because preloading for one row adds a query. The measured
single-record case and the list savings are owned by
[[lazy-inertia-props#Preload savings depend on result size]]. The same
row-scaled rule makes the memberships list preload its organizations and their
icons, because every row there draws one.

## Why the name search escapes its own wildcards

`?org_search=` narrows the index to organizations whose name contains the text,
in any case, and combines with the locale filter. `applied_filters` echoes it,
nil when absent.

The search runs in the database, before the 100-row limit, so a match past the
first hundred names is still found. SQLite's `LIKE` has no escape character
unless the query names one, so escaping `%` and `_` alone leaves them acting as
wildcards. The match names a backslash as its escape character, which makes a
search for `50%` find "50% Coalition" and not "500 Club".

The web page's search box writes `org_search` into the address after a short
pause and reloads only the list and the per-organization props. The locale and
the search both live in the address, so each survives a change to the other and
a reload. An empty result with a search names the search rather than the locale.

## Why the web list defaults to the current locale and JSON does not

The web page shows the reader's current locale, with the shared locale picker
to switch, the same shape the mobile list has
([[mobile-orgs-list-screen#OrgsListScreen]]).

An Inertia request with no locale parameter is therefore filtered by the
current locale and reports it in `applied_filters`. Without that default, the
picker would name one locale while the list showed all of them.

A JSON request with no locale parameter still returns every locale. The mobile
app leaves the locale parameter off when no locale is chosen, and narrowing that
request would change what the app shows.
