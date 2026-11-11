---
mode: explanation
summary: "Explains why pasteSummaryTriggerTestids.test.tsx deliberately renders both 'Paste summary JSON' triggers in one tree, pinning that their data-testids stay unique."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why pasteSummaryTriggerTestids.test.tsx renders both triggers together

The two "Paste summary JSON" buttons used to share the same `data-testid`.
A repeated testid does not fail loudly — a plain find/click silently acts
on whichever element comes back first.

This file deliberately renders both buttons in one tree. The point is not
that the app does that — it is that the app's identifiers must survive it.
