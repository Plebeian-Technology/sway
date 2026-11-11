---
lat:
  mode: explanation
---

# Why inertia_page_expired_error sets a machine-readable flag

`ApplicationController#inertia_page_expired_error` (the `InvalidAuthenticityToken` rescue) sets `flash[:page_expired] = true` alongside its human-facing message.

`ApplicationController#inertia_page_expired_error` (the `InvalidAuthenticityToken` rescue) sets `flash[:page_expired] = true` alongside its human-facing message — a refusal flagged twice: once for a person (the flash text) and once for code (`flash[:page_expired]`).

## Why alert:, not notice:

`registerFlashToasts` renders `flash.notice` as a SUCCESS toast, which would show "The page expired, please try again." in green — the wrong signal for a refused request.

## Why the redirect target and the flag both matter

`redirect_back_or_to("/")` lands the operator on the same URL a landed write redirects to.

A Bill Creator write handler that infers success from "did the redirect land" would otherwise read this refusal as a success — for example, showing "Summary saved." over a summary that had not actually changed.

`flash[:page_expired]` is the machine-readable flag those handlers check instead of the message text, so a later reword of the alert can't silently turn the check off. It is read by `app/frontend/sway_utils/pageExpired.ts`, and Bill Creator write handlers must call it before checking whether their own write landed — see [[docs/explanation/bill-creator-landed-write-detection.md|Bill Creator landed-write detection]] for the full write-detection picture this flag feeds into.

## Why IPageWithFlash.props is a bag, not { flash?: unknown }

`app/frontend/sway_utils/pageExpired.ts` types the parts of an Inertia page it reads as `props: Record<string, unknown>` rather than `{ flash?: unknown }`, so that Inertia's own `Page<PageProps>` satisfies it.

An interface of nothing but optional keys is a WEAK TYPE: TypeScript then refuses `Page<PageProps>` outright, on the grounds that it has no property in common with it.

## Why "save again" is the honest instruction, not "reload and save again"

Three Bill Creator write handlers used to answer `flash[:page_expired]` with "Reload and save again" — but no surface in this project may require a manual refresh.

The refresh has already happened by the time that flag reaches the browser: Inertia FOLLOWS `redirect_back_or_to("/")`'s redirect with a GET, that GET is an ordinary action, and `inertia_rails` writes a fresh `XSRF-TOKEN` cookie from its `after_action` on every such response. The operator already holds a fresh token by the time they read the message, so telling them to reload asks for a step that already happened invisibly. Retrying the write with the token they were already handed — no reload needed — is what makes "save again" the honest instruction.

## LlmSummaryEditableSummary's page-expired test note

A CSRF failure redirects back to the same URL (redirect_back_or_to via Referer), which landedOnBillCreator reads as proof the write landed — even though it didn't.

Reachable with no mistake — leave the Bill Creator open across a redeploy or session reset, then edit and save.

An expired CSRF token redirects BACK to this same URL, so a naive check would toast "Summary saved" over nothing written. No "reload" in the message: it already happened via that redirect.
