---
lat:
  mode: explanation
---

# Bill list layout constants and props contract

The bills index shares search, sort, and pagination constants across all theme layouts, while `BillListLayoutProps` defines the standard data contract passed to per-theme list components.

## Load more constants

Shared "load more" text ensures all theme layouts render, and tests target, the same pagination control.

`BILLS_LOAD_MORE_LABEL` and `BILLS_LOADING_MORE_LABEL` provide uniform copy for pagination triggers. This is a web-only capability; the mobile client fetches the full list instead. The growing-window pagination this label sits on top of operates as implemented by [[app/controllers/bills_controller.rb#BillsController]].

## Sort constants

Sort option constants define the allowed orderings and display labels for bill listings.

`BILLS_SORT_LABEL` and `BILLS_SORT_OPTIONS` encode `"<column>:<direction>"` pairs matching allowed database sort orders. The copy and options live in `PARITY_COPY` to maintain parity between web and mobile interfaces. `BILLS_SORT_VALUES` is declared at the module level so the sort hook's change handler maintains reference stability across renders.

## Search constants

Search constants configure client-side search input labels and placeholder text for bill filtering.

`BILLS_SEARCH_LABEL` and `BILLS_SEARCH_PLACEHOLDER` feed the search query parameter that filters bills by title. The search matches only against bill titles and coordinates with the total count returned by the server.

## BillListLayoutProps contract

The `BillListLayoutProps` interface defines the uniform props delivered to each theme-specific bill list component.

The parent page (`Bills.tsx`) owns filter state and data fetching, passing resolved bills, categories, sort options, list mode (`all_bills` vs `past_bills_of_the_month`), legislative session options, and jurisdiction display text down to the active layout. `onClearCategories` clears active category chips back to the full list, while `hasMoreBills` compares loaded bills against the server total.
