---
mode: explanation
summary: "Why Bill Creator editable-text fields re-seed from a refreshed server prop only when the field holds no unsaved edit, computed during render rather than in a useEffect."
status: agent-extracted
related: []
---

# Guarding an editable field against a stale-overwriting resync

Three Bill Creator fields hold operator-editable text backed by a server
column that can change underneath them without the component remounting:
`BillCreatorBillForm`'s summary field, `BillCreatorLlmSummary`'s
supplemental-testimony field, and
`LlmSummaryEditableSummary`'s published-summary field. All three
guard the same way.

## The problem

Inertia's polling (`usePoll`) and partial reloads refresh the page's props
— `bill`, `bill_llm_provisioning` — every few seconds without remounting
the component that reads them. `useForm(initialValues)` and a plain
`useState(serverValue)` both read their argument once, at mount, so
`form.data.summary` or a field's local state is a snapshot, not a live
mirror of the prop.

Seeding once is wrong in one direction: a tab left open while a column was
empty kept showing `""` forever, even after testimony or a summary existed
server-side. But always taking the newest server value on every render is
wrong in the other direction: a field mid-edit, or holding a just-pasted
value, would be silently overwritten the moment another operator's save —
or the poll itself — refreshed the prop.

## The guard

Track the server value the field was last synced to (`lastPublishedSummary`
/ `lastServerSupplemental`) alongside the field's own editable state. Each
render, compare the current server prop to that tracked value:

```ts
if (serverValue !== lastServerValue) {
    setLastServerValue(serverValue);
    if (fieldValue === lastServerValue) setFieldValue(serverValue);
}
```

The field only takes the new server value when it still holds the OLD
server value — i.e., the operator has no unsaved edit. A half-typed edit or
a mid-paste value survives another operator's save landing mid-edit.

This runs during render, not inside a `useEffect`, following React's
"adjusting state during rendering" pattern: no extra render pass, and no
flash of the old value before the effect fires.

## Why re-seeding once was the bug in both directions

`BillCreatorLlmSummary`'s supplemental-testimony field used to seed once at
mount, so a tab opened while the column was empty stayed empty forever,
even after testimony existed server-side. `LlmSummaryEditableSummary`
 took the new server value on every server change with no unsaved-
edit check, so a save from the Creator tab left the field stale and a
later Save on this tab silently wrote the stale text back over the newer
value. The comparison-against-`lastServerValue` guard is the one shape that
avoids both failures at once.

## Why BillCreatorLlmSummary's supplemental field remounts only on llm_generated_at changing

Only llm_generated_at changing remounts this component; a plain
useState(serverValue) would otherwise miss every later poll refresh of
`bill`.
