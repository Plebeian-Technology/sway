// A stand-in for virtual:pwa-register, a module that vite-plugin-pwa makes up
// at build time. Vitest points the import here so it resolves under jsdom, the
// fake browser tests run in. Any test file can still call vi.mock() to change
// the behaviour for itself.
import { vi } from "vitest";

export const registerSW = vi.fn<() => () => void>(() => vi.fn<() => void>());
