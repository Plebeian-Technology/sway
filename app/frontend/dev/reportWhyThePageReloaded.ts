import { describeReloadReason } from "app/frontend/dev/describeReloadReason";
import { appendReloadReason, readReloadReasons } from "app/frontend/dev/reloadReasonStore";
import { logDev } from "app/frontend/sway_utils";

// @lat: [[dev-reload-reason-diagnostic#What reportWhyThePageReloaded.test.ts is checking]]

// @lat: [[dev-reload-reason-diagnostic#How it works]]
const ANNOUNCED_BEFORE_A_RELOAD = ["vite:ws:disconnect", "vite:beforeFullReload", "vite:error"];

// @lat: [[dev-reload-reason-diagnostic#What reportWhyThePageReloaded.test.ts is checking]]
export interface IHotEvents {
    on: (event: string, listener: (payload: unknown) => void) => void;
}

// @lat: [[dev-reload-reason-diagnostic#Development only]]
export const reportWhyThePageReloaded = (hot: IHotEvents | undefined = import.meta.hot): void => {
    if (!hot || typeof window === "undefined") return;

    const storage = window.sessionStorage;
    const [navigation] = performance.getEntriesByType("navigation") as PerformanceNavigationTiming[];

    const message = describeReloadReason(
        readReloadReasons(storage),
        performance.timeOrigin,
        navigation?.type === "reload",
    );
    if (message) logDev(`[sway] ${message}`);

    for (const event of ANNOUNCED_BEFORE_A_RELOAD) {
        hot.on(event, () => {
            appendReloadReason(storage, {
                event,
                at: Date.now(),
                path: `${window.location.pathname}${window.location.search}`,
            });
        });
    }
};
