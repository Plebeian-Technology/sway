---
mode: explanation
summary: "Why several mobile navigation regression tests (AuthStack, AppTabs labels, header-title-audit) read source files as plain text instead of rendering, and why linking.test.ts checks the path pattern string instead of calling getStateFromPath."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Mobile navigation test guards

## Why AuthStack, AppTabs labels, and header-title-audit read source as plain text

`mobile/__tests__/AuthStack.routes.spec.ts`, `mobile/__tests__/navigation/AppTabs.labels.spec.ts`,
and `mobile/__tests__/navigation/header-title-audit.test.ts` all read their
target source files as plain text with `fs.readFileSync`, rather than
rendering with React Navigation or mocking anything. No React Navigation, no
rendering, no mocks — the whole file runs in under 100ms.

Do not mark any test in these files with `.skip` or `xtest` — a failure is
the warning signal these tests exist to give.

### `AuthStack.routes.spec.ts`: guard rail for the sign-in navigation stack

It must hold exactly two screens, Auth and DeviceUnsupported. These four
tests were written before the sign-in flow was shortened, so at first they
all failed on purpose — the stack still had six screens. They start passing
on their own once the extra screens are removed, and from then on they stop
the stack from growing back.

### `header-title-audit.test.ts`: guard rail for the back-button title in the header

It pins two things down by reading source text:

1. The back button on screens pushed inside the Organizations stack reads
   "Organizations", not "Orgs". That stack is the only one where the back
   title is at risk of drifting away from the tab label.
2. The shared page titles for the bills, legislators, orgs, and profile tab
   screens still hold the exact wording they were given.

### `AppTabs.labels.spec.ts`: guard rail for the five bottom-tab labels

Home, Bills, Legislators, Organizations, Profile. It stops a later edit to
`AppTabs.tsx` from quietly bringing the short "Orgs" label back, or from
dropping a `tabBarLabel` and letting the tab fall back to whatever the
screen's `name=` prop happens to say.

## Why `linking.test.ts` checks the path pattern string instead of calling `getStateFromPath`

React Navigation's `getStateFromPath` turns a path into the values a screen
receives. Through the `Profile.MembershipDetail` entry,
`/organizations/42/memberships/100` should come out as `orgId="42"` and
`id="100"`.

Running `getStateFromPath` for real needs the whole navigator tree, so this
test checks the path pattern string on its own instead. Opening a real link
and watching where it lands is verified by hand.

The `Profile.MembershipDetail` and `Profile.MembershipsList` route mappings
were written before `linking.ts` covered those screens, so at first they
failed on purpose.
