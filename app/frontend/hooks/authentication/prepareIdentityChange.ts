import { router } from "@inertiajs/react";
import consumer from "app/frontend/channels/consumer";
import { SWAY_STORAGE } from "app/frontend/sway_utils/storage";

export const IDENTITY_CHANGE_RETRY = "Sway could not finish updating. Reload this page and try again.";

const acknowledgesNetworkOnlyPages = (worker: ServiceWorker, signal?: AbortSignal): Promise<boolean> =>
    new Promise((resolve) => {
        const channel = new MessageChannel();
        const finish = (ready: boolean) => {
            clearTimeout(timer);
            signal?.removeEventListener("abort", abort);
            channel.port1.close();
            channel.port2.close();
            resolve(ready);
        };
        const abort = () => finish(false);
        const timer = setTimeout(() => finish(false), 1000);
        signal?.addEventListener("abort", abort, { once: true });
        channel.port1.onmessage = (event) => finish(event.data?.success === true);
        try {
            worker.postMessage({ type: "DYNAMIC_PAGES_NETWORK_ONLY" }, [channel.port2]);
        } catch {
            finish(false);
        }
    });

// @lat: [[client-caches-and-identity#Identity changes wait for network-only pages]]
const ensureNetworkOnlyPages = async (): Promise<void> => {
    if (!("serviceWorker" in navigator)) return;
    const container = navigator.serviceWorker;
    const current = container.controller;
    if (!current || (await acknowledgesNetworkOnlyPages(current))) return;
    if (!container.controller) return;

    const probes = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    let controllerChanged: (() => void) | undefined;
    let finished = false;
    const controllerReady = new Promise<void>((resolve) => {
        controllerChanged = () => {
            const worker = container.controller;
            if (!finished && worker)
                acknowledgesNetworkOnlyPages(worker, probes.signal)
                    .then((accepted) => accepted && resolve())
                    .catch(() => {});
        };
        container.addEventListener("controllerchange", controllerChanged);
    });
    const upgrade = Promise.resolve()
        .then(() => container.getRegistration())
        .then(async (registration) => {
            if (finished) return;
            if (!registration) throw new Error(IDENTITY_CHANGE_RETRY);
            await registration.update();
            controllerChanged?.();
        });
    const timeout = new Promise<never>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error(IDENTITY_CHANGE_RETRY)), 5000);
    });
    try {
        await Promise.race([Promise.all([upgrade, controllerReady]), timeout]);
    } finally {
        finished = true;
        probes.abort();
        clearTimeout(timer);
        if (controllerChanged) container.removeEventListener("controllerchange", controllerChanged);
    }
};

export const clearIdentityCaches = (): void => {
    router.cancelAll({ sync: false });
    router.flushAll();
    router.clearHistory();
    consumer.disconnect();
    localStorage.removeItem(SWAY_STORAGE.Local.BillCreator.Bill);
    localStorage.removeItem(SWAY_STORAGE.Local.BillCreator.Organizations);
    localStorage.removeItem(SWAY_STORAGE.Local.BillCreator.LegislatorVotes);
    for (let i = localStorage.length - 1; i >= 0; i--) {
        const key = localStorage.key(i);
        if (
            key &&
            (key.startsWith("@sway/localStorage/billCreator/summary/") || key.startsWith("sway:reported_bill_"))
        ) {
            localStorage.removeItem(key);
        }
    }
    localStorage.clear();
    sessionStorage.clear();
};

export const prepareIdentityChange = async (): Promise<void> => {
    await ensureNetworkOnlyPages();
    router.cancelAll();
    clearIdentityCaches();
};
