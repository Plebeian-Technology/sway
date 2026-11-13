---
lat:
  mode: explanation
---

# Mobile navigation test guards

Why several mobile navigation regression tests (AuthStack.

## Why AuthStack, AppDrawer labels, and header-title-audit read source as plain text

`mobile/__tests__/AuthStack.routes.spec.ts`.

`mobile/__tests__/AuthStack.routes.spec.ts`, `mobile/__tests__/navigation/AppDrawer.labels.spec.ts`, and `mobile/__tests__/navigation/header-title-audit.test.ts` all read their target source files as plain text with `fs.readFileSync`, rather than rendering with React Navigation or mocking anything. No React Navigation, no rendering, no mocks — the whole file runs in under 100ms.

Do not mark any test in these files with `.skip` or `xtest` — a failure is the warning signal these tests exist to give.

### AuthStack.routes.spec.ts: guard rail for the sign-in navigation stack

It must hold exactly two screens, Auth and DeviceUnsupported.

These four tests were written before the sign-in flow was shortened, so at first they all failed on purpose — the stack still had six screens. They start passing on their own once the extra screens are removed, and from then on they stop the stack from growing back.

### header-title-audit.test.ts: guard rail for the back-button title in the header

It pins two things down by reading source text:

1. The back button on screens pushed inside the Organizations stack reads
   "Organizations", not "Orgs". That stack is the only one where the back
   title is at risk of drifting away from the drawer label.
2. The shared page titles for the bills, legislators, orgs, and profile
   screens still hold the exact wording they were given.

### AppDrawer.labels.spec.ts: guard rail for the six drawer labels

Feed, Home, Bills, Legislators, Organizations, Profile.

It stops a later edit to `AppDrawer.tsx` from quietly bringing the short "Orgs" label back, or from dropping a `drawerLabel` and letting the item fall back to whatever the screen's `name=` prop happens to say.

## Why linking.test.ts checks the path pattern string instead of calling getStateFromPath

React Navigation's `getStateFromPath` turns a path into the values a screen receives. Through the `Profile.MembershipDetail` entry, `/organizations/42/memberships/100` should come out as `orgId="42"` and `id="100"`.

Running `getStateFromPath` for real needs the whole navigator tree, so this test checks the path pattern string on its own instead. Opening a real link and watching where it lands is verified by hand.

The `Profile.MembershipDetail` and `Profile.MembershipsList` route mappings were written before `linking.ts` covered those screens, so at first they failed on purpose.
