// @lat: [[mobile-sync-hooks#useReachability]]
import { useCallback, useEffect, useRef, useState } from "react";
import { addEventListener as addNetInfoListener } from "@react-native-community/netinfo";
import { API_BASE_URL } from "../constants/api";
import { Routes } from "../api/routes";

const TIMEOUT_MS = 10_000;
const POLL_INTERVAL_MS = 30_000;

export interface ReachabilityState {
    isOnline: boolean;
    lastChecked: Date;
    // @lat: [[mobile-sync-hooks#useReachability]]
    isResolved: boolean;
}

export const useReachability = (): ReachabilityState => {
    const [isOnline, setIsOnline] = useState<boolean>(false);
    const [lastChecked, setLastChecked] = useState<Date>(new Date());
    const [isResolved, setIsResolved] = useState<boolean>(false);
    const mountedRef = useRef<boolean>(false);

    const probe = useCallback(async (): Promise<void> => {
        let online = false;
        const controller = new AbortController();
        const id = setTimeout(() => controller.abort(), TIMEOUT_MS);
        try {
            const resp = await fetch(`${API_BASE_URL}${Routes.up()}`, {
                method: "HEAD",
                signal: controller.signal,
            });
            online = resp.ok;
        } catch {
            online = false;
        } finally {
            clearTimeout(id);
        }
        if (mountedRef.current) {
            setIsOnline(online);
            setLastChecked(new Date());
            setIsResolved(true);
        }
    }, []);

    useEffect(() => {
        mountedRef.current = true;
        probe().catch(() => undefined);

        const unsubscribeNet = addNetInfoListener((state) => {
            if (state.isConnected === false) {
                if (mountedRef.current) {
                    setIsOnline(false);
                    setLastChecked(new Date());
                    setIsResolved(true);
                }
            } else {
                probe().catch(() => undefined);
            }
        });

        const intervalId = setInterval(() => {
            probe().catch(() => undefined);
        }, POLL_INTERVAL_MS);

        return () => {
            mountedRef.current = false;
            unsubscribeNet();
            clearInterval(intervalId);
        };
    }, [probe]);

    return { isOnline, lastChecked, isResolved };
};
