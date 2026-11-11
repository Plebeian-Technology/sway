---
lat:
  mode: explanation
---

# Why the bill category screen does not need a second round trip

`BillCategoryOverride` used to follow each add and remove with `router.reload({ only: ["bill"] })`.

The write already answers with a redirect, and Inertia turns a redirect into a fresh GET of the page the operator is on — so the `bill` prop, and the `override_categories` inside it, are already current when that reload was fired. It was a second request for data the first one had just delivered, on a screen whose readers are assumed to be on much slower links than the machine running the tests.

## Why the guarantee lives in a request spec

Dropping the extra reload needs the guarantee to live somewhere, and it lives in `spec/requests/bills/categories_spec.rb` rather than in a component test.

Dropping the extra reload needs the guarantee to live somewhere, and it lives in `spec/requests/bills/categories_spec.rb` rather than in a component test: a component test with a fake router can only see which router method was called, never what the server actually sent back. Only a request spec that follows the redirect and inspects the resulting Inertia props can prove the `bill` prop already reflects the change.

## Why BillCategoryOverride reads props directly, with no prop drilling or useEffect

The section where an admin sets one bill's categories by hand. Sits on BillCreatorSummaryAndPositions, rendered only once the bill has been summarized.

override_categories and active_categories come only from bill_creator_props, sent on the Bill Creator path.

Reads the page props itself with usePage<...>(), so nothing has to be passed down through parent components. No useEffect: everything here is worked out from the server's props during render.

## Why the active-category counter only counts ACTIVE categories, and stays open when the limit prop is missing

Counts only ACTIVE categories against the limit, matching the assigner and CategoriesController ("no more than 3 active"). Switched-off leftovers show as removable chips but don't count.

The limit comes from the server (Category::MAX_ACTIVE_PER_BILL). When missing, the block stays open: the server still refuses and names the real limit, so the worst case is one wasted round trip. Optional because Inertia props are typed hopefully; missing means the admin is let through on purpose.

## Why remove/add use preserveScroll and check pageExpired before toasting

preserveScroll keeps the page from jumping to the top on remove (handleAdd's post does the same), carrying across the controller's redirect to keep the operator's place.

A CSRF-refused write lands here too (see pageExpired.ts) — toasting "Category removed" over an untouched row would be the same false claim the bill form's Save used to make. The same guard applies to handleAdd's onSuccess: a CSRF-refused write also lands here.

## Why remove/add still toast success even though there's no Save button

No Save button here — it saves on click — so without this toast, admins reach for the unrelated Save button below, meant for the arguments.

## Why remove/add toast explicit failure messages instead of failing silently

For remove: if the server refuses — because another tab already removed the link, for instance — this would fail without a word. Say so.

For add: the server refuses when the bill already has three active categories, or when this one was switched off in the meantime. Show that as a toast instead of swallowing it.

## Why category chips have no removal confirmation

The bill's current categories, each with an × to remove it. No confirmation: it is easy to undo.

## Why the add-category Select is keyed by the categories count

The key forces a brand-new Select after each add. Left alone, a Radix Select remembers its last-picked value, and re-picking it (e.g. re-adding a just-removed category) never fires onValueChange.

The aria-label sits on SelectTrigger, the element that actually carries role="combobox". SelectPrimitive.Root renders no HTML of its own, so a label there would vanish.

## Test setup notes for BillCreatorSummaryAndPositions.test.tsx

The page hosts editorial work after the pipeline finishes, with two children: BillCreatorLlmSummary and BillCreatorOrganizations. Each is replaced by a stable section-* div here.

The category widget: adding calls router.post, removing calls router.delete, three is the max, and each change makes exactly ONE request — the redirect Inertia follows re-renders the page.

Badge: a plain `<span>`, so the fake browser the tests run in (jsdom) can render the × remove buttons.

A plain browser `<select>`, so a test can pick a value with fireEvent.change instead of recreating Radix's pop-out menu (BillCreatorOrgPositionCard's test does the same).

Radix's Select root draws nothing; the trigger button is the real combobox with aria-label. This fake copies that label onto one `<select>` holding every `<option>`, so getByRole works.

Checks that a category edit shows up right away — the edit writes straight to /bills/:id/categories, and the partial reload sends the bill back rebuilt. No manual refresh, no full page load.

The fake router runs onSuccess right away, so the reload checks stay simple with no async setup.
