---
lat:
  mode: reference
---

# useConfirm/ConfirmProvider

A styled, promise-based replacement for the native `window.confirm()`. Mount `<ConfirmProvider>` once near the app root; call sites do:

```tsx
const confirm = useConfirm();
if (!(await confirm({ title: "Delete?", tone: "destructive" }))) return;
```

- The promise resolves `true` on confirm, `false` on cancel / overlay / Escape. It renders as a bottom sheet on phones and a centered card from `sm` up.

## Why settle keeps the title/description while closing

`settle` keeps the title/description in state while closing so the content does not blank out mid fade-out animation.
