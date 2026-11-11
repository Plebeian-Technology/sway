import { router, useForm } from "@inertiajs/react";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { sway } from "sway";

import { logDev, notify } from "app/frontend/sway_utils";

export type PushSupport = "supported" | "unsupported";

export const detectSupport = (): PushSupport => {
    if (typeof window === "undefined" || typeof navigator === "undefined") return "unsupported";
    if (!("serviceWorker" in navigator)) return "unsupported";
    if (!("PushManager" in window)) return "unsupported";
    if (!("Notification" in window)) return "unsupported";
    return "supported";
};

export interface UsePushSubscription {
    support: PushSupport;
    isEnabledHere: boolean;
    currentEndpoint: string | undefined;
    register: () => void;
    test: (e: React.MouseEvent<HTMLButtonElement>) => void;
    disable: (e: React.MouseEvent<HTMLButtonElement>) => void;
    processing: { register: boolean; test: boolean; disable: boolean };
}

export const usePushSubscription = (
    subscriptions: sway.notifications.IPushNotificationSubscription[],
): UsePushSubscription => {
    const support = useMemo(() => detectSupport(), []);

    const subscribeForm = useForm({ endpoint: "", p256dh: "", auth: "" });
    const destroyForm = useForm({ endpoint: "" });
    const testForm = useForm({ endpoint: "" });

    const [currentEndpoint, setCurrentEndpoint] = useState<string | undefined>(undefined);

    // @lat: [[push-subscriptions#Cross-referencing this device's subscription]]
    useEffect(() => {
        if (support !== "supported") return;

        let cancelled = false;

        navigator.serviceWorker
            .getRegistration()
            .then((r) => {
                if (cancelled) return;
                if (!r) {
                    setCurrentEndpoint(undefined);
                    return;
                }
                return r.pushManager.getSubscription().then((s) => {
                    if (cancelled) return;
                    setCurrentEndpoint(s?.endpoint);
                });
            })
            .catch(() => {
                if (cancelled) return;
                setCurrentEndpoint(undefined);
            });

        return () => {
            cancelled = true;
        };
    }, [subscriptions, support]);

    const thisDeviceSubscription = useMemo(() => {
        if (!currentEndpoint || !subscriptions) return undefined;
        return subscriptions.find((sub) => sub.endpoint === currentEndpoint);
    }, [subscriptions, currentEndpoint]);

    const isEnabledHere = Boolean(thisDeviceSubscription?.subscribed);

    const saveSubscription = useCallback(
        (sub: PushSubscription) => {
            const endpoint = sub.endpoint;
            const p256dh = btoa(String.fromCharCode(...new Uint8Array(sub.getKey("p256dh") as ArrayBuffer)));
            const auth = btoa(String.fromCharCode(...new Uint8Array(sub.getKey("auth") as ArrayBuffer)));

            // @lat: [[push-subscriptions#Why the subscribe form transforms its data]]
            subscribeForm.transform((current) => ({ ...current, endpoint, p256dh, auth }));
            subscribeForm.post("/notifications/push_notification_subscriptions", {
                preserveScroll: true,
                onSuccess: () => {
                    logDev("Subscription successfully saved on the server.");
                    setCurrentEndpoint(endpoint);
                    router.reload({ only: ["subscriptions"] });
                },
                onError: (errors) => console.error("Error saving subscription on the server:", errors),
            });
        },
        [subscribeForm],
    );

    const registerServiceWorker = useCallback(async () => {
        if (!("serviceWorker" in navigator) || !("VAPID_PUBLIC_KEY" in window)) return;
        try {
            // @lat: [[push-subscriptions#Why registration races against a timeout]]
            const reg = await Promise.race([
                navigator.serviceWorker.getRegistration(),
                new Promise<undefined>((r) => setTimeout(() => r(undefined), 3000)),
            ]);
            if (!reg) {
                notify({
                    level: "error",
                    title: "Push notifications could not be enabled — service worker is not available yet. Reload and try again.",
                });
                return;
            }
            // @lat: [[push-subscriptions#Why activation is awaited before subscribing]]
            if (!reg.active) {
                const target = reg.installing ?? reg.waiting;
                const ac = new AbortController();
                const activated = await Promise.race([
                    new Promise<boolean>((resolve) => {
                        if (!target) {
                            resolve(false);
                            return;
                        }
                        target.addEventListener(
                            "statechange",
                            () => {
                                if (target.state === "activated") resolve(true);
                            },
                            { signal: ac.signal },
                        );
                    }),
                    new Promise<boolean>((resolve) => setTimeout(() => resolve(false), 5000)),
                ]);
                ac.abort();
                if (!activated) {
                    notify({
                        level: "error",
                        title: "Push notifications could not be enabled — service worker did not finish activating. Reload and try again.",
                    });
                    return;
                }
            }
            // @lat: [[push-subscriptions#Why Enable discards the browser's existing subscription]]
            const existing = await reg.pushManager.getSubscription();
            if (existing) {
                try {
                    await existing.unsubscribe();
                } catch (error) {
                    console.error("Error removing the existing push subscription:", error);
                    notify({
                        level: "error",
                        title: "Push notifications could not be enabled — the old subscription on this device could not be removed. Reload and try again.",
                    });
                    return;
                }
            }
            const sub = await reg.pushManager.subscribe({
                userVisibleOnly: true,
                applicationServerKey: (window as Window & typeof globalThis & { VAPID_PUBLIC_KEY: string })
                    .VAPID_PUBLIC_KEY,
            });
            saveSubscription(sub);
        } catch (error) {
            console.error("Error during registration Service Worker:", error);
        }
    }, [saveSubscription]);

    const register = useCallback(() => {
        if ("Notification" in window) {
            Notification.requestPermission()
                .then((permission) => {
                    if (permission === "granted") {
                        registerServiceWorker().catch(console.error);
                    } else if (permission === "denied") {
                        console.error("User rejected to allow notifications.");
                        notify({
                            level: "error",
                            title: "Notifications were blocked by your browser.",
                        });
                    } else {
                        console.error("User still has not given an answer about notifications.");
                    }
                })
                .catch(console.error);
        } else {
            console.error("Push notifications not supported.");
            notify({
                level: "error",
                title: "Sorry, push notifications are not supported on this device.",
            });
        }
    }, [registerServiceWorker]);

    const test = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            navigator.serviceWorker
                .getRegistration()
                .then((r) => {
                    if (!r) return;
                    return r.pushManager.getSubscription().then((s) => {
                        if (s?.endpoint) {
                            testForm.transform((current) => ({ ...current, endpoint: s.endpoint }));
                            testForm.post("/notifications/push_notifications", {
                                preserveScroll: true,
                                preserveState: true,
                            });
                        }
                    });
                })
                .catch(console.error);
        },
        [testForm],
    );

    const disable = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            navigator.serviceWorker
                .getRegistration()
                .then((r) => {
                    if (!r) return;
                    return r.pushManager.getSubscription().then((s) => {
                        if (s?.endpoint) {
                            const endpoint = s.endpoint;
                            // @lat: [[push-subscriptions#Why the browser unsubscribes only after the server delete]]
                            destroyForm.transform((current) => ({ ...current, endpoint }));
                            destroyForm.delete("/notifications/push_notification_subscriptions", {
                                preserveScroll: true,
                                onSuccess: () => {
                                    s.unsubscribe().catch(console.error);
                                    setCurrentEndpoint(undefined);
                                    router.reload({ only: ["subscriptions"] });
                                },
                                onError: (errors) => {
                                    console.error("Error deleting subscription on the server:", errors);
                                    router.reload({ only: ["subscriptions"] });
                                },
                            });
                        }
                    });
                })
                .catch(console.error);
        },
        [destroyForm],
    );

    return {
        support,
        isEnabledHere,
        currentEndpoint,
        register,
        test,
        disable,
        processing: {
            register: subscribeForm.processing,
            test: testForm.processing,
            disable: destroyForm.processing,
        },
    };
};
