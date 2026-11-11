---
lat:
  mode: explanation
---

# The PARITY_COPY snapshot-testing pattern

User-facing strings are consolidated into `PARITY_COPY` constants to ensure web and mobile applications maintain identical, drift-free product wording.

Inertia pages centralize user-visible copy within `app/frontend/sway_constants/parityCopy.ts`. Both web components and native mobile screens consume these shared definitions.

## Why parity copy is tested via snapshots and duplicated in Ruby

Request specs maintain duplicate Ruby string constants to verify parity copy without requiring an embedded JavaScript runtime during backend test execution.

Reading `parityCopy.ts` directly from Ruby request specs would require a JavaScript runtime and DOM environment. Request specs compare serialized responses against pinned Ruby dictionary constants to catch accidental drifts.

## Why parityCopy.ts stands alone

`app/frontend/sway_constants/parityCopy.ts` stands alone without browser APIs or UI framework dependencies so web and mobile apps import identical copy without bundling conflicts.

The web application imports [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] directly or through its re-export, while the mobile client loads it through a relative module import. The file avoids browser globals, React components, and styling dependencies, ensuring both platforms share a single source of truth for customer-facing phrasing.

## Why parityCopy.test.ts checks the nested shape

`app/frontend/__tests__/parityCopy.test.ts` enforces nested object hierarchy across `PARITY_COPY` namespaces to prevent legacy flat camelCase keys from returning.

Earlier revisions exported flat identifiers such as `billsTitle`. Restructuring organized related wording under nested domains such as `bills.title`. [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] verifies nested accessor paths and asserts that root-level flat properties remain undefined.

## Mobile nested-key shape guard

The native mobile test suite confirms that shared product copy remains organized under nested object domains rather than flat identifiers.

Native mobile screens import [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] through relative module paths. Enforcing nested object properties in [[mobile/__tests__/parityCopy.spec.ts]] prevents flat legacy root keys from resurfacing and maintains structural parity with web consumers.
