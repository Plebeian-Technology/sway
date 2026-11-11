---
mode: explanation
summary: "Why ui/table.tsx is a manually-scaffolded shadcn Table primitive with no virtualization, and where PerBillGrid's own virtualizer lives instead."
status: agent-extracted
related: []
---

# Why `ui/table.tsx` has no virtualization

`ui/table.tsx` is a shadcn Table primitive (new-york style) — added via
manual scaffold for `ResourceCachePanel`. Standard
shadcn semantic HTML + Tailwind tokens; matches the new-york preset used
elsewhere in `components/ui/`. No virtualization here — `PerBillGrid`
does its own virtualizer integration with inline semantic markup.
