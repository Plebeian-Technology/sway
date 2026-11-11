import { useCallback, useEffect, useRef, useState } from "react";
import { logDev } from "app/frontend/sway_utils";
import { useTime } from "app/frontend/hooks/useTime";

const HEARTBEAT_URL = "/up";
const TIMEOUT_MS = 3000;
const POLL_INTERVAL_MS = 30_000;

export interface ReachabilityState {
    isOnline: boolean;
    lastChecked: Date;
}

export const useReachability = (): ReachabilityState => {
    const date = useTime();

    const [isOnline, setIsOnline] = useState<boolean>(
        typeof navigator !== "undefined" ? navigator.onLine !== false : true,
    );
    const [lastChecked, setLastChecked] = useState<Date>(date);
    const mountedRef = useRef<boolean>(false);

    const probe = useCallback(async (): Promise<void> => {
        if (typeof navigator !== "undefined" && navigator.onLine === false) {
            if (mountedRef.current) {
                setIsOnline(false);
                setLastChecked(new Date());
            }
            return;
        }
        let online = false;
        try {
            const controller = new AbortController();
            const id = setTimeout(() => controller.abort(), TIMEOUT_MS);
            const resp = await fetch(HEARTBEAT_URL, {
                method: "HEAD",
                signal: controller.signal,
                cache: "no-store",
                credentials: "same-origin",
            });
            clearTimeout(id);
            online = resp.ok;
        } catch (error) {
            logDev("useReachability: heartbeat failed", error);
            online = false;
        }
        if (mountedRef.current) {
            setIsOnline(online);
            setLastChecked(new Date());
        }
    }, []);

    useEffect(() => {
        mountedRef.current = true;
        probe().catch(() => undefined);
        const handleOnline = () => {
            probe().catch(() => undefined);
        };
        const handleOffline = () => {
            if (mountedRef.current) {
                setIsOnline(false);
                setLastChecked(new Date());
            }
        };
        window.addEventListener("online", handleOnline);
        window.addEventListener("offline", handleOffline);
        const intervalId = window.setInterval(() => {
            probe().catch(() => undefined);
        }, POLL_INTERVAL_MS);
        return () => {
            mountedRef.current = false;
            window.removeEventListener("online", handleOnline);
            window.removeEventListener("offline", handleOffline);
            window.clearInterval(intervalId);
        };
    }, [probe]);

    return { isOnline, lastChecked };
};
