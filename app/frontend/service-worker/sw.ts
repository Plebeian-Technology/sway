/// <reference lib="webworker" />

import { cleanupOutdatedCaches, precacheAndRoute } from "workbox-precaching";
import { registerRoute } from "workbox-routing";
import { CacheFirst } from "workbox-strategies";
import { ExpirationPlugin } from "workbox-expiration";
import { CacheableResponsePlugin } from "workbox-cacheable-response";
import { parsePushPayload } from "app/frontend/service-worker/parsePushPayload";
import { resolveNotificationClickUrl } from "app/frontend/service-worker/resolveNotificationClickUrl";

declare const self: ServiceWorkerGlobalScope & { __WB_MANIFEST: Array<{ url: string; revision: string | null }> };

precacheAndRoute(self.__WB_MANIFEST);
cleanupOutdatedCaches();

// @lat: [[client-caches-and-identity#What the page cache is allowed to hold]]
export const NO_STORE_PATTERN = /(^|,)\s*no-(store|cache)\s*(=|,|$)/i;
export const CacheControlPlugin = {
    async cacheWillUpdate({ response }: { response: Response }): Promise<Response | null> {
        const cacheControl = response.headers.get("Cache-Control");
        return cacheControl !== null && NO_STORE_PATTERN.test(cacheControl) ? null : response;
    },
};

// @lat: [[admin-chunks-are-not-precached#Why the precache excludes them]]
export const ADMIN_ASSET_PATTERN = /\/assets\/admin\//;
export function isAdminAsset(url: URL): boolean {
    return url.origin === self.location.origin && ADMIN_ASSET_PATTERN.test(url.pathname);
}
registerRoute(
    ({ url, request }) =>
        request.mode !== "navigate" && request.headers.get("X-Inertia") !== "true" && isAdminAsset(url),
    new CacheFirst({
        cacheName: "admin-assets",
        plugins: [
            new CacheableResponsePlugin({ statuses: [200] }),
            new ExpirationPlugin({ maxEntries: 60, maxAgeSeconds: 60 * 60 * 24 * 30 }),
            CacheControlPlugin,
        ],
    }),
);

// @lat: [[client-caches-and-identity#Static worker lifecycle]]
self.addEventListener("install", (event) => {
    event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", (event) => {
    event.waitUntil(
        (async () => {
            await Promise.all([caches.delete("inertia-pages"), caches.delete("inertia-navigations")]);
            await self.clients.claim();
        })(),
    );
});

self.addEventListener("message", (event) => {
    if (event.data?.type === "DYNAMIC_PAGES_NETWORK_ONLY") {
        event.ports[0]?.postMessage({ success: true });
        return;
    }
    if ((event.data as any)?.type === "SKIP_WAITING") {
        self.skipWaiting().catch(() => {});
        return;
    }
    if ((event.data as any)?.type === "PURGE_CACHES") {
        // @lat: [[client-caches-and-identity#Static worker lifecycle]]
        event.waitUntil(
            (async () => {
                const cacheNames = await caches.keys();
                await Promise.all(cacheNames.map((name) => caches.delete(name)));
                (event.ports[0] as MessagePort | undefined)?.postMessage({ success: true });
            })(),
        );
    }
});

// @lat: [[client-caches-and-identity#Push delivery]]
self.addEventListener("push", (event: PushEvent) => {
    if (!event.data) return;
    const rawText = event.data.text();
    const notificationData = parsePushPayload(rawText);
    if (!notificationData) {
        event.waitUntil(self.registration.showNotification("Sway", { body: rawText }));
        return;
    }
    const options: NotificationOptions = {
        body: notificationData.body,
        icon: notificationData.icon,
        data: notificationData.data,
    };
    event.waitUntil(self.registration.showNotification(notificationData.title ?? "Sway", options));
});

self.addEventListener("notificationclick", (event: NotificationEvent) => {
    event.notification.close();
    const data = event.notification.data as { url?: string } | undefined;
    const safeUrl = resolveNotificationClickUrl(data?.url, self.location.origin);
    event.waitUntil(
        // @lat: [[client-caches-and-identity#Push delivery]]
        self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
            // @lat: [[client-caches-and-identity#Push delivery]]
            for (const client of clientList) {
                if (new URL(client.url).origin === self.location.origin && "focus" in client) {
                    const wc = client as WindowClient;
                    return wc.navigate(safeUrl).then((navigated) => (navigated ?? wc).focus());
                }
            }
            if (self.clients.openWindow) {
                return self.clients.openWindow(safeUrl);
            }
        }),
    );
});
