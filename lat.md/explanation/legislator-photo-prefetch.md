---
lat:
  mode: explanation
---
# Prefetching a reader's own legislator photos

`ApplicationController#current_user_legislator_photo_urls` supplies the photo URLs [[app/frontend/components/layouts/AuthLayout.tsx#AuthLayout]] turns into `<link>` tags, so the browser can fetch representative photos while idle.

## Why it prefetches images instead of preloading them

The layout wraps every page, so a `preload` tag would take priority away from whatever the page is actually showing — `prefetch` does not.

Safari ignores `prefetch` entirely, which is no worse than not asking at all.

## Why the candidate set is narrowed before the term filter runs

The method reads in three steps — the reader's own active representatives in this jurisdiction, then which of those are currently serving, then their portraits — because the middle step is expensive if it is not handed a narrow candidate list first.

Locale scoping filters on `legislators.sway_locale_id` directly rather than joining through `district`, because that join would `INNER JOIN` through `active_term` and silently drop any legislator with no current term; "currently serving" comes from `LegislatorTerm.current` instead, which replaced the removed `legislators.active` column. `LegislatorTerm.current` is not a `WHERE` clause — it loads its candidate terms into Ruby (`includes(district: :sway_locale).to_a`), asks `TermWindow` which one is running today for each legislator, and only then returns `where(id: winners)`. Reaching it through the `:active_term` association, as a prior version did, handed it no candidates to narrow, so it read every term row in the database — and reading the legislator's `district` went through the same association and paid it again. That cost about 2.5 million object allocations and 1.5 seconds on every full render for every signed-in reader, on pages such as `/terms` that show no legislators at all; handing `LegislatorTerm.current` an explicit `legislator_id` list first brought the same six addresses back for about 3,600 allocations and 4ms. The scope no longer reads the whole table for anyone — it bounds its candidates by date in SQL first, which is [[current-legislator-term#Why the candidates are bounded in SQL first|its own decision]] — but narrowing by `legislator_id` here still matters, because that bound leaves every currently-serving term in the country, not this reader's six.

## Why the photo attachment and blob are preloaded

The final load asks for `preload(photo_attachment: :blob)`, because resolving a photo URL asks `MirroredAssetUrl.for` whether a local copy exists — a database question.

Without preloading, that would cost one extra attachment query per representative on every page a signed-in reader opens. `preload` rather than `includes`, because a single `where` on a joined table pushes Rails onto its `eager_load` path, building one wide join for no gain when the block reads nothing but `photo` and `photo_url`; `:district` is not loaded by this reader-specific load.

The Bill page resolves roster and sponsor portraits through [[app/serializers/bill_page_legislator_resource.rb#BillPageLegislatorResource]], which uses [[app/services/mirrored_asset_url.rb#MirroredAssetUrl]]. [[app/serializers/bill_page_resource.rb#BillPageResource]] chains `with_active_term.preload(photo_attachment: :blob)` for both the session roster and its active-locale fallback, avoiding per-representative attachment, active-term, and district queries in either branch. The full Bill Creator new form uses [[app/models/legislator.rb#Legislator#to_builder]] and chains `with_active_term.preload(photo_attachment: :blob)` before serializing its active roster; its callable prop is skipped on narrower polls. The shared request guard measures actual serialized rows, photo attachment/blob reads, and total SQL query counts across these paths.
