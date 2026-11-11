// @lat: [[mobile-session-hook#The announcements it listens for]]
import { useCallback, useEffect, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { tokenStore } from "../auth/tokenStore";
import { sessionStore } from "../auth/sessionStore";
import { authEvents } from "../auth/authEvents";
import { purgeAll } from "../cache/db";
import { bootstrapCache } from "../cache/bootstrapCache";
import { destroyConsumer } from "../channels/consumer";
import { clearCapturedCategories } from "./useBills";

export interface SignOutOptions {
    skipServerRevoke?: boolean;
}

export interface UseSessionResult {
    isAuthenticated: boolean;
    loading: boolean;
    signOut: (options?: SignOutOptions) => Promise<void>;
    signOutAll: () => Promise<void>;
}

const CACHE_WIPE_TIMEOUT_MS = 2000;

let inFlightWipe: Promise<void> | null = null;

async function runWipeLocalCaches(): Promise<void> {
    clearCapturedCategories();
    const cacheWipe = Promise.all([purgeAll(), bootstrapCache.purge()]).then(() => undefined);
    let timeoutId: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<void>((resolve) => {
        timeoutId = setTimeout(resolve, CACHE_WIPE_TIMEOUT_MS);
    });
    try {
        await Promise.race([cacheWipe, timeout]);
    } catch (e) {
        // oxlint-disable-next-line no-console
        console.error("useSession: cache wipe failed", e);
    } finally {
        clearTimeout(timeoutId);
    }
    try {
        destroyConsumer();
    } catch (e) {
        // oxlint-disable-next-line no-console
        console.error("useSession: destroyConsumer failed", e);
    }
}

function wipeLocalCaches(): Promise<void> {
    if (inFlightWipe) return inFlightWipe;
    inFlightWipe = runWipeLocalCaches().finally(() => {
        inFlightWipe = null;
    });
    return inFlightWipe;
}

export function useSession(): UseSessionResult {
    const [isAuthenticated, setIsAuthenticated] = useState<boolean>(false);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let cancelled = false;
        (async () => {
            // @lat: [[mobile-session-hook#The announcements it listens for]]
            try {
                const sess = await sessionStore.get();
                if (cancelled) return;
                setIsAuthenticated(!!sess?.bearer_token);
            } catch (e) {
                // oxlint-disable-next-line no-console
                console.error("useSession: session read failed", e);
                if (cancelled) return;
                setIsAuthenticated(false);
            } finally {
                if (!cancelled) setLoading(false);
            }
        })();

        const unsub = authEvents.on((e) => {
            if (e === "signed_in") setIsAuthenticated(true);
            else if (e === "signed_out" || e === "unauthenticated") {
                setIsAuthenticated(false);
                // @lat: [[mobile-session-hook#Why unauthenticated also wipes on-device caches]]
                if (e === "unauthenticated") {
                    void wipeLocalCaches();
                }
            }
        });

        return () => {
            cancelled = true;
            unsub();
        };
    }, []);

    const signOut = useCallback(async (options?: SignOutOptions) => {
        // @lat: [[mobile-session-hook#The announcements it listens for]]
        if (!options?.skipServerRevoke) {
            const sess = await sessionStore.get();
            if (sess?.device_id) {
                try {
                    await apiClient.delete(Routes.deviceDestroy(sess.device_id));
                } catch {}
            }
        }

        await tokenStore.clear();
        await sessionStore.clear();
        await wipeLocalCaches();

        authEvents.emit("signed_out");
    }, []);

    const signOutAll = useCallback(async () => {
        try {
            await apiClient.post(Routes.sessionsRevokeAll(), {});
        } catch {}

        await tokenStore.clear();
        await sessionStore.clear();
        await wipeLocalCaches();

        authEvents.emit("signed_out");
    }, []);

    return { isAuthenticated, loading, signOut, signOutAll };
}
