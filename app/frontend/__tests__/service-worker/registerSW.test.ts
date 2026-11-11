import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { registerPWA } from "@/service-worker/registerSW";
import { registerSW } from "virtual:pwa-register";

// @lat: [[client-caches-and-identity#Static worker lifecycle]]
describe("registerPWA", () => {
    let originalNavigator: Navigator;
    let warnSpy: ReturnType<typeof vi.spyOn>;
    let errorSpy: ReturnType<typeof vi.spyOn>;

    beforeEach(() => {
        vi.clearAllMocks();
        originalNavigator = globalThis.navigator;
        warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
        errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    });

    afterEach(() => {
        warnSpy.mockRestore();
        errorSpy.mockRestore();
        Object.defineProperty(globalThis, "navigator", {
            value: originalNavigator,
            configurable: true,
            writable: true,
        });
    });

    it("does nothing when navigator has no serviceWorker property", () => {
        Object.defineProperty(globalThis, "navigator", {
            value: {},
            configurable: true,
            writable: true,
        });

        registerPWA();

        expect(registerSW).not.toHaveBeenCalled();
    });

    it("registers the service worker when supported", () => {
        Object.defineProperty(globalThis, "navigator", {
            value: { serviceWorker: {} },
            configurable: true,
            writable: true,
        });

        registerPWA();

        expect(registerSW).toHaveBeenCalledWith(
            expect.objectContaining({
                immediate: false,
                onNeedReload: expect.any(Function),
                onRegisterError: expect.any(Function),
            }),
        );
    });

    it("logs registration failures via console.warn and not console.error", () => {
        Object.defineProperty(globalThis, "navigator", {
            value: { serviceWorker: {} },
            configurable: true,
            writable: true,
        });

        registerPWA();

        const registerSWCall = vi.mocked(registerSW).mock.calls[0][0];
        const dummyError = new TypeError("Failed to register a ServiceWorker: ServiceWorker cannot be started");

        registerSWCall?.onRegisterError?.(dummyError);

        expect(warnSpy).toHaveBeenCalledWith("registerPWA: SW registration failed", dummyError);
        expect(errorSpy).not.toHaveBeenCalled();
    });
});
