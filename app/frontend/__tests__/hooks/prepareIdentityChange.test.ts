import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const router = vi.hoisted(() => ({
    cancelAll: vi.fn<(options?: { sync: boolean }) => void>(),
    flushAll: vi.fn<() => void>(),
    clearHistory: vi.fn<() => void>(),
}));
const consumer = vi.hoisted(() => ({
    disconnect: vi.fn<() => void>(),
}));
vi.mock("@inertiajs/react", () => ({ router }));
vi.mock("app/frontend/channels/consumer", () => ({ default: consumer }));
import { clearIdentityCaches, prepareIdentityChange } from "app/frontend/hooks/authentication/prepareIdentityChange";

const worker = (acknowledges: boolean) => ({
    postMessage: vi.fn<(message: unknown, ports: { reply: () => void }[]) => void>(
        (_message: unknown, ports: { reply: () => void }[]) => {
            if (acknowledges) ports[0].reply();
        },
    ),
});

const installContainer = (controller: ReturnType<typeof worker> | null) => {
    const container = Object.assign(new EventTarget(), {
        controller,
        getRegistration: vi.fn<() => Promise<{ update: () => Promise<void> } | undefined>>(),
    });
    Object.defineProperty(navigator, "serviceWorker", { configurable: true, value: container });
    return container;
};

describe("prepareIdentityChange", () => {
    beforeEach(() => {
        vi.useFakeTimers();
        vi.clearAllMocks();
        localStorage.setItem("previous-user-draft", "private");
        sessionStorage.setItem("previous-user-state", "private");
        vi.stubGlobal(
            "MessageChannel",
            class {
                port1 = {
                    onmessage: null as ((event: { data: { success: boolean } }) => void) | null,
                    close: vi.fn<() => void>(),
                };
                port2 = {
                    close: vi.fn<() => void>(),
                    reply: () => this.port1.onmessage?.({ data: { success: true } }),
                };
            },
        );
    });
    afterEach(() => {
        vi.useRealTimers();
        vi.unstubAllGlobals();
        Reflect.deleteProperty(navigator, "serviceWorker");
    });

    it("clears identity caches before returning when no worker controls the page", async () => {
        installContainer(null);
        await prepareIdentityChange();
        expect(router.cancelAll).toHaveBeenCalledTimes(2);
        expect(router.cancelAll.mock.invocationCallOrder[0]).toBeLessThan(router.flushAll.mock.invocationCallOrder[0]);
        expect(router.flushAll.mock.invocationCallOrder[0]).toBeLessThan(
            router.clearHistory.mock.invocationCallOrder[0],
        );
        expect(localStorage.length).toBe(0);
        expect(sessionStorage.length).toBe(0);
        expect(consumer.disconnect).toHaveBeenCalled();
    });

    it("disconnects ActionCable consumer and removes billCreator and reported_bill localStorage keys", () => {
        localStorage.setItem("@sway/creator/bill", '{"id":1}');
        localStorage.setItem("@sway/creator/organizations", "[]");
        localStorage.setItem("@sway/localStorage/billCreator/summary/42", "draft");
        localStorage.setItem("sway:reported_bill_42", "true");
        const removeItemSpy = vi.spyOn(Storage.prototype, "removeItem");

        clearIdentityCaches();

        expect(consumer.disconnect).toHaveBeenCalledOnce();
        expect(removeItemSpy).toHaveBeenCalledWith("@sway/creator/bill");
        expect(removeItemSpy).toHaveBeenCalledWith("@sway/creator/organizations");
        expect(removeItemSpy).toHaveBeenCalledWith("@sway/localStorage/billCreator/summary/42");
        expect(removeItemSpy).toHaveBeenCalledWith("sway:reported_bill_42");
        expect(localStorage.length).toBe(0);
        removeItemSpy.mockRestore();
    });

    it("clears data repopulated during submission before applying the destination", async () => {
        installContainer(null);
        await prepareIdentityChange();
        localStorage.setItem("previous-user-draft", "late old-page write");
        let cachedResponse: string | null = "previous user's prefetched response";
        router.flushAll.mockImplementationOnce(() => {
            cachedResponse = null;
        });
        clearIdentityCaches();
        expect(cachedResponse).toBeNull();
        expect(localStorage.length).toBe(0);
        expect(router.cancelAll).toHaveBeenLastCalledWith({ sync: false });
    });

    it("keeps a current worker registered after its policy acknowledgement", async () => {
        const current = worker(true);
        const container = installContainer(current);
        await prepareIdentityChange();
        expect(current.postMessage.mock.calls[0][0]).toEqual({ type: "DYNAMIC_PAGES_NETWORK_ONLY" });
        expect(container.getRegistration).not.toHaveBeenCalled();
        expect(router.flushAll).toHaveBeenCalledOnce();
    });

    it("can proceed when the old controller disappears during the probe", async () => {
        const container = installContainer(worker(false));
        const pending = prepareIdentityChange();
        container.controller = null;
        await vi.advanceTimersByTimeAsync(1000);
        await pending;
        expect(container.getRegistration).not.toHaveBeenCalled();
        expect(router.flushAll).toHaveBeenCalledOnce();
    });

    it("waits for the upgraded controller before clearing or allowing submission", async () => {
        const container = installContainer(worker(false));
        const remove = vi.spyOn(container, "removeEventListener");
        container.getRegistration.mockResolvedValue({
            update: vi.fn<() => Promise<void>>().mockResolvedValue(undefined),
        });
        const pending = prepareIdentityChange();
        await vi.advanceTimersByTimeAsync(1000);
        expect(router.flushAll).not.toHaveBeenCalled();
        container.controller = worker(true);
        container.dispatchEvent(new Event("controllerchange"));
        await pending;
        expect(router.flushAll).toHaveBeenCalledOnce();
        expect(remove).toHaveBeenCalledWith("controllerchange", expect.any(Function));
        await vi.advanceTimersByTimeAsync(0);
        expect(vi.getTimerCount()).toBe(0);
    });

    it("rejects a failed update and preserves the current user's storage", async () => {
        const container = installContainer(worker(false));
        container.getRegistration.mockResolvedValue({
            update: vi.fn<() => Promise<void>>().mockRejectedValue(new Error("offline")),
        });
        const pending = prepareIdentityChange().catch((error: unknown) => error);
        await vi.advanceTimersByTimeAsync(1000);
        await expect(pending).resolves.toBeInstanceOf(Error);
        expect(router.flushAll).not.toHaveBeenCalled();
        expect(localStorage.getItem("previous-user-draft")).toBe("private");
    });

    it("bounds an unresponsive upgrade and removes its listener", async () => {
        const container = installContainer(worker(false));
        const remove = vi.spyOn(container, "removeEventListener");
        container.getRegistration.mockReturnValue(new Promise(() => {}));
        const pending = prepareIdentityChange().catch((error: unknown) => error);
        await vi.advanceTimersByTimeAsync(6000);
        await expect(pending).resolves.toBeInstanceOf(Error);
        expect(router.flushAll).not.toHaveBeenCalled();
        expect(remove).toHaveBeenCalledOnce();
        await vi.advanceTimersByTimeAsync(0);
        expect(vi.getTimerCount()).toBe(0);
    });
});
