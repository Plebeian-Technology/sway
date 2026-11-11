import { registerSW } from "virtual:pwa-register";

// @lat: [[client-caches-and-identity#Static worker lifecycle]]
export function preserveOpenPageOnWorkerUpdate(): void {}

export function registerPWA(): void {
    if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) return;
    registerSW({
        immediate: false,
        onNeedReload: preserveOpenPageOnWorkerUpdate,
        onRegisterError: (error) => {
            console.warn("registerPWA: SW registration failed", error);
        },
    });
}
