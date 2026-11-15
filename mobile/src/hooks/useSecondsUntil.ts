import { useCallback, useSyncExternalStore } from "react";

import { secondsUntil } from "../../../app/frontend/sway_utils/resendCooldown";

// @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#The cooldown clock on Send a new code]]
export const useSecondsUntil = (untilMs: number | null): number => {
    const subscribe = useCallback(
        (onTick: () => void) => {
            if (untilMs === null) return () => undefined;
            const timer = setInterval(() => {
                onTick();
                if (Date.now() >= untilMs) clearInterval(timer);
            }, 1000);
            return () => clearInterval(timer);
        },
        [untilMs],
    );
    const getSnapshot = useCallback(() => secondsUntil(untilMs, Date.now()), [untilMs]);

    return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
};
