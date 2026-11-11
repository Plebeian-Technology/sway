---
lat:
  mode: explanation
---

# Paste summary dialog

A pasted summary remains a draft until the operator deliberately copies it into the published-summary editor and saves it.

## The dialog validates a pasted draft before publishing

The request path writes a provisioning draft. The browser example catches redirect errors and keeps the dialog open.

## A published summary remains separate from the pasted draft

The fixture names its published summary because the factory supplies a generated paragraph. Explicit text makes it clear that paste must not change the public column.

## Validation waits for the server response

The helper waits until Validate is enabled after setting the textarea. React has not necessarily rerendered when Capybara's set returns, so clicking immediately can hit a disabled control.

## The setup has existing drafts and supplemental testimony

The provisioning row makes the dialog available. Existing drafts prove that a successful pasted positions payload replaces the old set, and testimony ensures the service does not take its no-testimony drop path.

## Fixture names form stable card selectors

The pasted organization has a distinct name from the existing draft. Its card can appear only if the service saved the pasted positions.

## Publishing replaces the previous positions set

The happy path checks the new card appears, the prior draft disappears, and no dropped-positions notice appears. Those assertions distinguish replacement from a payload silently discarded for missing testimony.

## The rejected payload leaves the published summary unchanged

The rejection example waits for server errors before asserting the dialog remains open; the dialog was already open before submission. Its malformed payload omits required summary text because positions are optional in the current schema.
