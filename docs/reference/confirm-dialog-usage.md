---
mode: reference
summary: "How to use useConfirm/ConfirmProvider, the styled promise-based replacement for window.confirm(), and why its content stays populated while closing."
status: agent-extracted
related: []
---

# `useConfirm`/`ConfirmProvider`

A styled, promise-based replacement for the native `window.confirm()`.
Mount `<ConfirmProvider>` once near the app root; call sites do:

```tsx
const confirm = useConfirm();
if (!(await confirm({ title: "Delete?", tone: "destructive" }))) return;
```

The promise resolves `true` on confirm, `false` on cancel / overlay /
Escape. It renders as a bottom sheet on phones and a centered card from
`sm` up.

## Why `settle` keeps the title/description while closing

`settle` keeps the title/description in state while closing so the
content does not blank out mid fade-out animation.
