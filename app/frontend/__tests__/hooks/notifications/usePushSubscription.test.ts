import { renderHook, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

const notifyMock = vi.fn<(...args: unknown[]) => void>();
vi.mock("app/frontend/sway_utils", () => ({
    notify: (...args: unknown[]) => notifyMock(...args),
    logDev: vi.fn<() => void>(),
}));

const reloadMock = vi.fn<(options?: unknown) => void>();
const destroyMock = vi.fn<(url: string, config?: unknown) => void>();
const postMock = vi.fn<(url: string, config?: unknown) => void>();
const transformMock = vi.fn<(callback: (data: Record<string, string>) => Record<string, string>) => void>();

vi.mock("@inertiajs/react", () => ({
    router: { reload: (options?: unknown) => reloadMock(options) },
    useForm: () => ({
        data: {},
        setData: vi.fn<(key: string, value: unknown) => void>(),
        post: (url: string, config?: unknown) => postMock(url, config),
        delete: (url: string, config?: unknown) => destroyMock(url, config),
        transform: (callback: (data: Record<string, string>) => Record<string, string>) => transformMock(callback),
        processing: false,
    }),
}));

import {
    detectSupport,
    type UsePushSubscription,
    usePushSubscription,
} from "app/frontend/hooks/notifications/usePushSubscription";

type Sub = sway.notifications.IPushNotificationSubscription;

const sub = (endpoint: string, subscribed: boolean): Sub => ({ endpoint, subscribed }) as Sub;

type DisableEvent = Parameters<UsePushSubscription["disable"]>[0];

const clickEvent = () => ({ preventDefault: () => {} }) as unknown as DisableEvent;

interface DeleteConfig {
    preserveScroll?: boolean;
    onSuccess: () => void;
    onError: (errors: unknown) => void;
}

const deleteConfig = (): DeleteConfig => destroyMock.mock.calls[0][1] as DeleteConfig;

const define = (target: object, key: string, value: unknown) =>
    Object.defineProperty(target, key, { value, configurable: true, writable: true });

/** Pretend the browser has all three Push API pieces. The caller supplies getRegistration. */
const stubSupported = (getRegistration: () => Promise<unknown> = () => Promise.resolve(undefined)) => {
    define(navigator, "serviceWorker", { getRegistration });
    define(window, "PushManager", function PushManager() {});
    define(window, "Notification", { requestPermission: vi.fn<() => Promise<string>>().mockResolvedValue("default") });
};

const clearSupported = () => {
    delete (navigator as unknown as Record<string, unknown>).serviceWorker;
    delete (window as unknown as Record<string, unknown>).PushManager;
    delete (window as unknown as Record<string, unknown>).Notification;
    delete (window as unknown as Record<string, unknown>).VAPID_PUBLIC_KEY;
};

const browserSubscription = (
    endpoint: string,
    unsubscribe = vi.fn<() => Promise<boolean>>().mockResolvedValue(true),
) => ({
    endpoint,
    unsubscribe,
    getKey: (name: string) => new TextEncoder().encode(`${name}-bytes`).buffer,
});

const stubGrantedRegistration = (pushManager: object) => {
    stubSupported(() => Promise.resolve({ active: {}, pushManager }));
    define(window, "Notification", { requestPermission: vi.fn<() => Promise<string>>().mockResolvedValue("granted") });
    define(window, "VAPID_PUBLIC_KEY", "current-key");
};

const savedEndpoint = (): string => transformMock.mock.calls[0][0]({ endpoint: "", p256dh: "", auth: "" }).endpoint;

describe("detectSupport", () => {
    afterEach(clearSupported);

    it("reports unsupported when the Push API capabilities are absent", () => {
        expect(detectSupport()).toBe("unsupported");
    });

    it("reports supported when serviceWorker, PushManager and Notification all exist", () => {
        stubSupported();
        expect(detectSupport()).toBe("supported");
    });

    it("reports unsupported when Notification is missing", () => {
        define(navigator, "serviceWorker", { getRegistration: vi.fn<() => Promise<unknown>>() });
        define(window, "PushManager", function PushManager() {});
        expect(detectSupport()).toBe("unsupported");
    });
});

describe("usePushSubscription", () => {
    beforeEach(() => {
        notifyMock.mockClear();
        reloadMock.mockClear();
        destroyMock.mockClear();
        postMock.mockClear();
        transformMock.mockClear();
    });
    afterEach(clearSupported);

    it("exposes an unsupported, disabled state when the Push API is absent", () => {
        const { result } = renderHook(() => usePushSubscription([]));
        expect(result.current.support).toBe("unsupported");
        expect(result.current.isEnabledHere).toBe(false);
        expect(result.current.currentEndpoint).toBeUndefined();
        expect(result.current.processing).toEqual({ register: false, test: false, disable: false });
    });

    it("does not touch navigator.serviceWorker while unsupported", () => {
        renderHook(() => usePushSubscription([]));
        expect((navigator as unknown as Record<string, unknown>).serviceWorker).toBeUndefined();
    });

    it("marks this device enabled when its endpoint matches a subscribed record", async () => {
        const registration = {
            pushManager: { getSubscription: () => Promise.resolve({ endpoint: "ep-here" }) },
        };
        stubSupported(() => Promise.resolve(registration));

        const { result } = renderHook(() => usePushSubscription([sub("ep-here", true)]));

        await waitFor(() => expect(result.current.isEnabledHere).toBe(true));
        expect(result.current.currentEndpoint).toBe("ep-here");
    });

    it("leaves this device disabled when its endpoint matches an unsubscribed record", async () => {
        const registration = {
            pushManager: { getSubscription: () => Promise.resolve({ endpoint: "ep-here" }) },
        };
        stubSupported(() => Promise.resolve(registration));

        const { result } = renderHook(() => usePushSubscription([sub("ep-here", false)]));

        await waitFor(() => expect(result.current.currentEndpoint).toBe("ep-here"));
        expect(result.current.isEnabledHere).toBe(false);
    });

    it("unsubscribes the browser only once the server delete has succeeded", async () => {
        const unsubscribe = vi.fn<() => Promise<boolean>>().mockResolvedValue(true);
        const registration = {
            pushManager: { getSubscription: () => Promise.resolve({ endpoint: "ep-here", unsubscribe }) },
        };
        stubSupported(() => Promise.resolve(registration));

        const { result } = renderHook(() => usePushSubscription([sub("ep-here", true)]));
        await waitFor(() => expect(result.current.currentEndpoint).toBe("ep-here"));

        result.current.disable(clickEvent());

        await waitFor(() => expect(destroyMock).toHaveBeenCalledTimes(1));
        expect(destroyMock.mock.calls[0][0]).toBe("/notifications/push_notification_subscriptions");
        expect(deleteConfig().preserveScroll).toBe(true);
        expect(unsubscribe).not.toHaveBeenCalled();

        deleteConfig().onSuccess();

        expect(unsubscribe).toHaveBeenCalledTimes(1);
        expect(reloadMock).toHaveBeenCalledWith({ only: ["subscriptions"] });
    });

    it("keeps the browser subscribed and re-reads the server list when the delete fails", async () => {
        const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
        const unsubscribe = vi.fn<() => Promise<boolean>>().mockResolvedValue(true);
        const registration = {
            pushManager: { getSubscription: () => Promise.resolve({ endpoint: "ep-here", unsubscribe }) },
        };
        stubSupported(() => Promise.resolve(registration));

        const { result } = renderHook(() => usePushSubscription([sub("ep-here", true)]));
        await waitFor(() => expect(result.current.currentEndpoint).toBe("ep-here"));

        result.current.disable(clickEvent());

        await waitFor(() => expect(destroyMock).toHaveBeenCalledTimes(1));

        deleteConfig().onError({ endpoint: "could not be removed" });

        expect(unsubscribe).not.toHaveBeenCalled();
        expect(reloadMock).toHaveBeenCalledWith({ only: ["subscriptions"] });
        consoleError.mockRestore();
    });

    // @lat: [[push-subscriptions#Why Enable discards the browser's existing subscription]]
    it("replaces an existing browser subscription with one made from the current key on Enable", async () => {
        const stale = browserSubscription("ep-stale");
        const fresh = browserSubscription("ep-fresh");
        const subscribe = vi.fn<(options: PushSubscriptionOptionsInit) => Promise<unknown>>().mockResolvedValue(fresh);
        stubGrantedRegistration({ getSubscription: () => Promise.resolve(stale), subscribe });

        const { result } = renderHook(() => usePushSubscription([]));
        result.current.register();

        await waitFor(() => expect(postMock).toHaveBeenCalledTimes(1));
        expect(stale.unsubscribe).toHaveBeenCalledTimes(1);
        expect(subscribe).toHaveBeenCalledWith({ userVisibleOnly: true, applicationServerKey: "current-key" });
        expect(stale.unsubscribe.mock.invocationCallOrder[0]).toBeLessThan(subscribe.mock.invocationCallOrder[0]);
        expect(postMock.mock.calls[0][0]).toBe("/notifications/push_notification_subscriptions");
        expect(savedEndpoint()).toBe("ep-fresh");
    });

    it("subscribes with the current key when the browser holds no subscription", async () => {
        const fresh = browserSubscription("ep-fresh");
        const subscribe = vi.fn<(options: PushSubscriptionOptionsInit) => Promise<unknown>>().mockResolvedValue(fresh);
        stubGrantedRegistration({ getSubscription: () => Promise.resolve(null), subscribe });

        const { result } = renderHook(() => usePushSubscription([]));
        result.current.register();

        await waitFor(() => expect(postMock).toHaveBeenCalledTimes(1));
        expect(subscribe).toHaveBeenCalledWith({ userVisibleOnly: true, applicationServerKey: "current-key" });
        expect(savedEndpoint()).toBe("ep-fresh");
    });

    it("saves nothing and reports an error when the existing subscription cannot be removed", async () => {
        const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
        const stale = browserSubscription(
            "ep-stale",
            vi.fn<() => Promise<boolean>>().mockRejectedValue(new Error("unsubscribe failed")),
        );
        const subscribe = vi.fn<(options: PushSubscriptionOptionsInit) => Promise<unknown>>();
        stubGrantedRegistration({ getSubscription: () => Promise.resolve(stale), subscribe });

        const { result } = renderHook(() => usePushSubscription([]));
        result.current.register();

        await waitFor(() => expect(notifyMock).toHaveBeenCalledWith(expect.objectContaining({ level: "error" })));
        expect(stale.unsubscribe).toHaveBeenCalledTimes(1);
        expect(subscribe).not.toHaveBeenCalled();
        expect(postMock).not.toHaveBeenCalled();
        consoleError.mockRestore();
    });

    it("notifies an error when the browser denies the notification permission", async () => {
        stubSupported();
        (window as unknown as { Notification: { requestPermission: () => Promise<string> } }).Notification = {
            requestPermission: vi.fn<() => Promise<string>>().mockResolvedValue("denied"),
        };

        const { result } = renderHook(() => usePushSubscription([]));
        result.current.register();

        await waitFor(() =>
            expect(notifyMock).toHaveBeenCalledWith(
                expect.objectContaining({ level: "error", title: "Notifications were blocked by your browser." }),
            ),
        );
    });
});
