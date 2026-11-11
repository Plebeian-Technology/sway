---
mode: explanation
summary: "Why Bill Creator write handlers check the URL a redirect landed on instead of trusting Inertia's onSuccess/onError callbacks."
status: agent-extracted
related: []
---

# Bill Creator landed-write detection

`landedOnBillCreator` (`app/frontend/components/admin/creator/billCreatorLanding.ts`) tells a
write handler whether the Inertia visit that just finished actually landed back on this bill's
Bill Creator page. Several Bill Creator surfaces — `PasteSummaryDialog`, `BillCreatorLlmSummary`,
`LlmSummaryEditableSummary`, `useRegenerateSummary` — call it after a save, alongside
`pageExpired` (`app/frontend/sway_utils/pageExpired.ts`).

## Why the landing page, not the callback

Inertia calls `onError` only for a response carrying an errors bag. A redirect that lands on a
valid page is a SUCCESSFUL visit and calls `onSuccess` — so "the request came back 200" is not
"the write landed". `verify_is_sway_admin` sends a lapsed admin session to `/`, which used to end
in a green "Summary saved." toast over a public summary that was unchanged — worse than saying
nothing.

## One reachable case, not two

A bill destroyed in another tab can't reach `landedOnBillCreator` at all: `set_bill` resolves with
`find`, which raises `RecordNotFound` for a destroyed bill — a 404, which Inertia does not treat
as a successful visit, so `onSuccess` never runs for it. The non-landing message this function
backs is worded off what is OBSERVED — nothing was written — rather than off a cause. Naming the
lapsed session as the cause is right only because it's the one reachable case, and would quietly
go wrong the moment a second redirect appeared.

Every write on this screen redirects back to a tab of `/admin/bill_creator/:id`, so that prefix is
the one thing a landed write and a refused one cannot share.

### LlmSummaryEditableSummary's defensive non-bill-landing test

`BillsController#update`'s `@bill.blank?` guard is unreachable — `find` raises RecordNotFound
before it, so this redirect never really happens.

Kept as defensive coverage even though the server can't reach this state — the invariant (no
non-bill landing page reads as success) still holds.

## One refusal shares it — call pageExpired first

`ApplicationController` rescues `InvalidAuthenticityToken` with `inertia_page_expired_error`,
which redirects back to the current page via `Referer` — landing a refused save on the very URL a
real save lands on. Callers must call `pageExpired(page)` FIRST for this reason; the server sets a
flag for it rather than leaving the browser to match on a sentence (see `pageExpired.ts` for why a
flag beats matching flash text).

## Prefix matching, not `startsWith`

`landedOnBillCreator` checks the character right after the id rather than a bare `startsWith`,
because `/admin/bill_creator/12` starts with `/admin/bill_creator/1`.

```ts
export const landedOnBillCreator = (url: string, billId: number): boolean => {
    const base = `/admin/bill_creator/${billId}`;
    if (!url.startsWith(base)) return false;
    const next = url.charAt(base.length);
    return next === "" || next === "/" || next === "?" || next === "#";
};
```

## `useBillFormSubmit` skips clearing the dirty flag on a refused save

A page-expired visit lands back on this same page as an ordinary successful
Inertia visit (see `pageExpired.ts`), so `onSuccess` alone cannot tell a
landed save from a refused one. `useBillFormSubmit` skips clearing the
dirty flag when the write never happened.

The defect it prevents: a refused save was clearing the unsaved-changes flag anyway,
telling the operator their edits were saved when the server took nothing.
`useBillFormSubmit.test.ts` pins this.

## LlmSummaryEditableSummary's handleSaveSummary

Decided on the LANDING PAGE, not which callback ran: a lapsed admin
session comes back as a successful-looking Inertia REDIRECT, so
`onSuccess` must check where it actually landed.

Without a dedicated `onError` handler, a refused save said nothing: the
shared flash-to-toast code reads only `flash.notice`/`flash.alert`, and
nothing in this component renders `props.errors` — so a validation
failure looked identical to success.
