---
mode: explanation
summary: "Why SwayFormContext holds InertiaFormProps<any> rather than a typed generic, with each caller narrowing via useSwayFormContext<T>()."
status: agent-extracted
related: []
---

# Why `SwayFormContext` is untyped, narrowed per caller

The new-UI version of `app/frontend/components/contexts/SwayFormContext.ts`,
same shape so later Bill Creator code can keep calling
`useSwayFormContext<T>()` unchanged.

Same shape as the older `SwayFormContext`: the type parameter is `any`
here, and each caller pins the real type down with calls like
`useSwayFormContext<IApiBillCreator>()`.
