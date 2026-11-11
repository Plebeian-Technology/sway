// A stand-in for virtual:pwa-register/react, a module that vite-plugin-pwa
// makes up at build time. Vitest points the import here so it resolves under
// jsdom, the fake browser tests run in. Any test file can still call vi.mock()
// to change the behaviour for itself.
import { vi } from "vitest";

export const useRegisterSW = vi.fn<
    () => {
        needRefresh: [boolean, (v: boolean) => void];
        offlineReady: [boolean, (v: boolean) => void];
        updateServiceWorker: () => void;
    }
>(() => ({
    needRefresh: [false, vi.fn<(v: boolean) => void>()] as [boolean, (v: boolean) => void],
    offlineReady: [false, vi.fn<(v: boolean) => void>()] as [boolean, (v: boolean) => void],
    updateServiceWorker: vi.fn<() => void>(),
}));
