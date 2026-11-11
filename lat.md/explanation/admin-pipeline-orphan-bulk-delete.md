---
lat:
  mode: explanation
  require-code-mention: true
---

# Admin pipeline orphan bulk-delete browser test

The system example drives the orphan-run delete flow through the browser, server response, flash, partial reload, and database.

## The browser follows the complete delete loop

Request specs cover the endpoint; the system example proves the button, confirmation, delete response, activity entry, flash, and updated page work together.

## Orphan rows are deterministic in the test database

The test database does not contain corresponding Solid Queue jobs, so it stubs orphan? as true instead of relying on queue-table state or a rescue fallback.

## The app dialog is the confirmation surface

The delete control uses Sway's React confirmation dialog rather than window.confirm. The test clicks the dialog's own action because browser confirmation helpers cannot operate that application dialog.

## Wait for the rendered count to reach zero

The delete can finish before the Inertia progress bar appears. Waiting for the orphan button to disappear confirms the partial reload reflected the new count before the example reads the database.
