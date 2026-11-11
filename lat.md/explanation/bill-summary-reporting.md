---
lat:
  mode: explanation
---

# Bill summary reporting

When AI models summarize legislative texts, readers can identify factual errors, slanted phrasing, or unreflected amendments. Sway provides in-app reporting for readers and a triage workspace for administrators.

## Reader reporting of inaccurate summaries

Readers encounter an unreviewed notice bar below AI-generated bill summaries. The bar offers an external link to official bill text and a reporting modal to capture reader feedback with structured reasons.

Whenever a bill identity exists, reporting remains available independently of source link presence or reviewed status. The notice bar displays the official source link when valid, or the shared unavailable notice when absent or generic, while preserving the report button for all persisted bills. Preview text without a bill identity remains non-reportable.

The reporting modal presents four structured categories: factual inaccuracy, misleading tone or bias, missing amendment or outdated text, and other issues. In addition, the reader provides descriptive details citing specific bill provisions. On the website, submissions from unauthenticated readers are permitted as guest reports, capturing the client IP address using deterministic encryption.

When a report is created, the system records an immutable snapshot of the bill's current summary text and whether the summary was unreviewed. This ensures administrators evaluate the report against the exact text the reader saw, even if subsequent pipeline runs regenerate the summary.

### Reporting from the mobile Bill tab

The mobile Bill tab shows a "Report inaccurate summary" text control under the summary card. A signed-in reader gets a report sheet from it, and a guest gets the shared sign-in prompt.

[[mobile/src/components/BillScreenTabs.tsx#BillScreenTabs]] draws the control for every bill that has an identity, unless [[app/frontend/components/bill/sway_utils/billArchiving.ts#isArchivedHistoricalBill]] holds: the bill is inactive and has no scheduled release date. That is the website's rule, and the shared function keeps the two platforms from drifting. A summary that still reads as pending keeps the control.

Guests are sent to sign in because the website accepts guest reports without a token, while a phone request skips CSRF protection only when it carries a validated bearer token ([[identity-and-access#Identity and access#Sessions, cookies and bearer tokens]]). A guest request from the phone would be rejected, and accepting it needs a server-side carve-out that the mobile app does not assume.

[[mobile/src/components/ReportSummarySheet.tsx#ReportSummarySheet]] repeats the website dialog's input rules on the client: one of the four reasons, and details of at least 10 characters after trimming and at most 2000. The server enforces only the 2000 cap, so the 10-character floor exists on both platforms only in the client. The trimmed details are what the request carries, nested under `bill_summary_report` with the reason.

[[mobile/src/hooks/useReportSummary.ts#useReportSummary]] sorts every response into one outcome:

- A created report shows the thank-you copy.
- Any 422 shows the already-submitted copy. With the reason and length rules checked before sending, the 24-hour duplicate window is the only validation the server can still reject.
- A 429 asks the reader to wait, a network failure says Sway could not be reached, and any other failure gets a generic retry message.

Every failure keeps the form filled so the reader can send again. The sheet keeps no record of a sent report, so reopening it shows an empty form, and a second report inside the window comes back as the already-submitted message; the website stores a marker in local storage instead.

## Public endpoint rate limiting and duplicate bounds

The public reporting route enforces rate limits and duplicate throttling to protect the application against abuse. Requests are bounded per IP address and per bill.

Rate limits restrict clients to five report submissions per hour using Sway's cache-backed rate limiter. Additionally, duplicate submissions from the same IP address or user account on the same bill are throttled within a twenty-four hour window. The client interface caches successful reports in local storage, replacing the submission form with a confirmation view upon return.

## Admin triage and remediation

Administrators triage reader reports at `/admin/bill_summary_reports`, filtering by status and jurisdiction. Each report links directly into the Bill Creator for immediate summary revision.

Reports progress through four statuses: pending, reviewed, resolved, and dismissed. The triage interface displays status counts across tabs, allows filtering by locale and search keyword, and provides responsive desktop table and mobile card layouts.

Remediating a reported summary involves navigating into the Bill Creator summary tab via deep links. Once revised or evaluated, administrators mark reports as resolved or dismissed with optional administrative notes, recording the resolving administrator and timestamp.

## System verification for reader reports and admin triage

End-to-end system specifications exercise both reader reporting from the public bill page and administrative triage within the operator console.

The test suite verifies that the unreviewed notice bar renders with the external source link and report button. Clicking the button opens the dialog, validates form inputs, and records a snapshot upon submission. The admin suite verifies navigation from the admin hub, status filtering, resolution modals, and deep links into the Bill Creator summary editor.
