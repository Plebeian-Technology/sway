import consumer from "app/frontend/channels/consumer";
import { logDev } from "app/frontend/sway_utils";
import { router } from "@inertiajs/react";
import { useCallback } from "react";

// @lat: [[logout-service-worker-purge-order#Why local/session storage is cleared in onFinish, not onSuccess]]
async function purgeServiceWorker(): Promise<void> {
    if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) return;
    try {
        const reg = await Promise.race([
            navigator.serviceWorker.getRegistration(),
            new Promise<undefined>((r) => setTimeout(() => r(undefined), 2000)),
        ]);
        if (!reg) return;

        const active = reg.active ?? navigator.serviceWorker.controller;
        if (active) {
            await new Promise<void>((resolve) => {
                const channel = new MessageChannel();
                const timer = setTimeout(resolve, 2000);
                channel.port1.onmessage = () => {
                    clearTimeout(timer);
                    resolve();
                };
                active.postMessage({ type: "PURGE_CACHES" }, [channel.port2]);
            });
        }
        await reg.unregister();
    } catch (error) {
        console.error("useLogout: purgeServiceWorker failed", error);
    }
}

export const useLogout = () => {
    return useCallback(async () => {
        logDev("useLogout: Starting logout process");
        logDev("useLogout: Purging service worker caches and unregistering...");
        await purgeServiceWorker().catch(console.error);
        logDev("useLogout: Service worker purge/unregister complete. Sending logout request...");
        router.delete("/users/webauthn/sessions/0", {
            preserveScroll: false,
            onError: (errors) => {
                console.error("useLogout: router.delete failed", errors);
            },
            // @lat: [[logout-service-worker-purge-order#Why local/session storage is cleared in onFinish, not onSuccess]]
            onFinish: () => {
                // @lat: [[logout-service-worker-purge-order#Why router.flushAll() runs alongside the storage clears]]
                consumer.disconnect();
                router.flushAll();
                localStorage.clear();
                sessionStorage.clear();
            },
        });
    }, []);
};
