import { renderHook, act } from "@testing-library/react";
import { vi, describe, it, expect, beforeEach } from "vitest";

const routerDeleteMock = vi.fn<
    (
        url: string,
        options?: {
            preserveScroll?: boolean;
            onError?: (e: unknown) => void;
            onFinish?: () => void;
        },
    ) => void
>();
const routerFlushAllMock = vi.fn<() => void>();
vi.mock("@inertiajs/react", () => ({
    router: { delete: routerDeleteMock, flushAll: routerFlushAllMock },
}));

// @lat: [[frontend-test-infrastructure-notes#Warming a module transform out of a test's own budget]]
await import("app/frontend/hooks/users/useLogout");

describe("useLogout", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        // Forget the modules already loaded, so each test imports a fresh copy
        // of useLogout. Each test sets navigator.serviceWorker before it
        // imports.
        vi.resetModules();
        // By default there is no service worker. `userAgent` still has to
        // exist, because app/frontend/sway_constants/index.ts reads it the
        // moment it loads, and useLogout pulls that in through sway_utils.
        Object.defineProperty(globalThis, "navigator", {
            value: { userAgent: "vitest", serviceWorker: undefined },
            configurable: true,
        });
    });

    it("calls router.delete /users/webauthn/sessions/0 even without serviceWorker", async () => {
        const { useLogout } = await import("app/frontend/hooks/users/useLogout");
        const { result } = renderHook(() => useLogout());
        await act(async () => {
            await result.current();
        });
        expect(routerDeleteMock).toHaveBeenCalledWith(
            "/users/webauthn/sessions/0",
            expect.objectContaining({ preserveScroll: false }),
        );
    });

    it("posts PURGE_CACHES and unregisters SW before router.delete when SW present", async () => {
        const postMessage = vi.fn<(message: Record<string, unknown>, ports: MessagePort[]) => void>();
        const unregister = vi.fn<() => Promise<boolean>>().mockResolvedValue(true);
        const channelPort1Set = vi.fn<(fn: (e: MessageEvent) => void) => void>();
        const registration = { active: { postMessage }, unregister };

        class MockMessageChannel {
            port1 = {
                set onmessage(fn: (e: MessageEvent) => void) {
                    channelPort1Set(fn);
                    // pretend the service worker answered
                    queueMicrotask(() => fn({ data: { success: true } } as MessageEvent));
                },
            };
            port2 = {} as MessagePort;
        }
        (globalThis as any).MessageChannel = MockMessageChannel;

        // useLogout finds the service worker through
        // navigator.serviceWorker.getRegistration(), not .ready. Fake both, in
        // case that changes later, and have getRegistration hand back the same
        // registration object that carries active.postMessage and unregister.
        Object.defineProperty(globalThis, "navigator", {
            value: {
                userAgent: "vitest",
                serviceWorker: {
                    ready: Promise.resolve(registration),
                    getRegistration: () => Promise.resolve(registration),
                    controller: registration.active,
                },
            },
            configurable: true,
        });

        const { useLogout } = await import("app/frontend/hooks/users/useLogout");
        const { result } = renderHook(() => useLogout());
        await act(async () => {
            await result.current();
        });

        expect(postMessage).toHaveBeenCalledWith({ type: "PURGE_CACHES" }, expect.any(Array));
        expect(unregister).toHaveBeenCalledTimes(1);
        expect(routerDeleteMock).toHaveBeenCalled();
        // They must run in this order: postMessage, unregister, router.delete.
        expect(postMessage.mock.invocationCallOrder[0]).toBeLessThan(unregister.mock.invocationCallOrder[0]);
        expect(unregister.mock.invocationCallOrder[0]).toBeLessThan(routerDeleteMock.mock.invocationCallOrder[0]);
    });

    // Clearing storage happens in onFinish, not onSuccess, so that a DELETE
    // that FAILS — where onError runs and onSuccess never does — still wipes
    // the local state.
    it("clears local + session storage in onFinish even when the DELETE fails", async () => {
        localStorage.setItem("stale-local", "value");
        sessionStorage.setItem("stale-session", "value");
        routerDeleteMock.mockImplementation(
            (_url: string, opts?: { onError?: (e: unknown) => void; onFinish?: () => void }) => {
                // Act out a failed request: no onSuccess, just onError then onFinish.
                opts?.onError?.({});
                opts?.onFinish?.();
            },
        );

        const { useLogout } = await import("app/frontend/hooks/users/useLogout");
        const { result } = renderHook(() => useLogout());
        await act(async () => {
            await result.current();
        });

        expect(localStorage.getItem("stale-local")).toBeNull();
        expect(sessionStorage.getItem("stale-session")).toBeNull();
        expect(localStorage.length).toBe(0);
        expect(sessionStorage.length).toBe(0);

        routerDeleteMock.mockReset();
    });

    // @lat: [[logout-service-worker-purge-order#Why router.flushAll() runs alongside the storage clears]]
    it("flushes the Inertia prefetch cache in onFinish", async () => {
        routerDeleteMock.mockImplementation((_url: string, opts?: { onFinish?: () => void }) => {
            opts?.onFinish?.();
        });

        const { useLogout } = await import("app/frontend/hooks/users/useLogout");
        const { result } = renderHook(() => useLogout());
        await act(async () => {
            await result.current();
        });

        expect(routerFlushAllMock).toHaveBeenCalledTimes(1);

        routerDeleteMock.mockReset();
    });
});
