import { afterEach, describe, expect, it, vi } from "vitest";
import { registerSW } from "virtual:pwa-register";
import { preserveOpenPageOnWorkerUpdate, registerPWA } from "app/frontend/service-worker/registerSW";

vi.mock("virtual:pwa-register", () => ({ registerSW: vi.fn<(...args: unknown[]) => unknown>() }));

afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
});

// @lat: [[client-caches-and-identity#Static worker lifecycle]]
describe("registerPWA", () => {
    it("registers after load without permitting the plugin to reload an open form", () => {
        vi.stubGlobal("navigator", { serviceWorker: {} });
        registerPWA();
        expect(registerSW).toHaveBeenCalledWith({
            immediate: false,
            onNeedReload: preserveOpenPageOnWorkerUpdate,
            onRegisterError: expect.any(Function),
        });
    });

    it("skips registration when service workers are unavailable", () => {
        vi.stubGlobal("navigator", {});
        registerPWA();
        expect(registerSW).not.toHaveBeenCalled();
    });
});
