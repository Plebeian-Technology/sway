// @lat: [[mobile-bootstrap-lifecycle#Where bootstrap data is stored, and why]]
import React, { createContext, useContext, useEffect, useState, useCallback, useRef } from "react";
import { AppState, AppStateStatus } from "react-native";
import Constants from "expo-constants";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { UnauthorizedError } from "../api/errors";
import { bootstrapCache } from "../cache/bootstrapCache";
import { purgeAll } from "../cache/db";
import { prefsCache, PREFS_KEYS } from "../cache/prefsCache";
import { destroyConsumer } from "../channels/consumer";
import { sessionStore } from "../auth/sessionStore";
import { tokenStore } from "../auth/tokenStore";
import { authEvents } from "../auth/authEvents";
import { localeOverride } from "./localeOverride";
import type { Locale } from "../utils/locale";

export interface Bootstrap {
    current_user: { id?: number; theme_mode?: string | null } | null;
    locale: Locale | null;
    sway_locales: Locale[];
    bill_of_the_month?: Record<string, unknown> | null;
    feature_flags: Record<string, boolean>;
    unread_notification_count: number;
    min_supported_version: string;
    latest_version: string;
}

export interface BootstrapContextValue {
    bootstrap: Bootstrap | null;
    loading: boolean;
    error: Error | null;
    // @lat: [[mobile-locale-override-design#The lifecycle of the override value]]
    refetch: (swayLocaleId?: number) => Promise<boolean>;
    selectedSwayLocaleId: number | null;
    needsUpdate: boolean;
}

const BootstrapCtx = createContext<BootstrapContextValue | null>(null);

// @lat: [[mobile-bootstrap-lifecycle#What happens, in order]]
const STALE_MS = 5 * 60 * 1000;

export function BootstrapProvider({ children }: { children: React.ReactNode }) {
    const [bootstrap, setBootstrap] = useState<Bootstrap | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const [selectedSwayLocaleId, setSelectedSwayLocaleId] = useState<number | null>(null);
    const lastFetchedRef = useRef<number | null>(null);
    const hydratedRef = useRef<boolean>(false);

    const applyLocaleOverride = useCallback(async (id: number | null) => {
        localeOverride.set(id);
        setSelectedSwayLocaleId(id);
        if (id == null) await prefsCache.delete(PREFS_KEYS.selectedSwayLocaleId);
        else await prefsCache.set(PREFS_KEYS.selectedSwayLocaleId, String(id));
    }, []);

    const fetchIt = useCallback(
        async (swayLocaleId?: number): Promise<boolean> => {
            setLoading(true);
            setError(null);
            if (swayLocaleId != null) {
                await applyLocaleOverride(swayLocaleId);
            }
            try {
                // @lat: [[mobile-bootstrap-lifecycle#Why the fetch checks whether it expected to be signed in]]
                const hadBearer = (await tokenStore.get()) != null;
                const b = await apiClient.get<Bootstrap>(Routes.bootstrap());
                if (hadBearer && b.current_user == null) {
                    await tokenStore.clear();
                    await sessionStore.clear();
                    await bootstrapCache.purge();
                    // @lat: [[mobile-locale-override-design#Why BootstrapContext clears the choice when the session ends outside sign-out]]
                    localeOverride.clear();
                    setSelectedSwayLocaleId(null);
                    await prefsCache.delete(PREFS_KEYS.selectedSwayLocaleId);
                    setBootstrap(null);
                    authEvents.emit("unauthenticated");
                    return false;
                }
                setBootstrap(b);
                lastFetchedRef.current = Date.now();
                const userId = b.current_user?.id ? String(b.current_user.id) : "anonymous";
                await bootstrapCache.set(userId, b);
                return true;
            } catch (e: unknown) {
                const err = e instanceof Error ? e : new Error(String(e));
                setError(err);
                // @lat: [[mobile-bootstrap-lifecycle#Why a 401 wipes the cache instead of falling back to it]]
                if (err instanceof UnauthorizedError) {
                    setBootstrap(null);
                    await bootstrapCache.purge();
                    return false;
                }
                const sess = await sessionStore.get();
                const cached =
                    (sess?.user_id != null ? await bootstrapCache.get<Bootstrap>(String(sess.user_id)) : null) ??
                    (await bootstrapCache.get<Bootstrap>("anonymous"));
                if (cached) {
                    setBootstrap(cached.payload);
                    lastFetchedRef.current = cached.fetchedAt.getTime();
                }
                return false;
            } finally {
                setLoading(false);
            }
        },
        [applyLocaleOverride],
    );

    // @lat: [[locale-name-is-derived#A locale's name is derived, not stored#The picker's options are formatted before they leave the server]]
    useEffect(() => {
        if (hydratedRef.current) return;
        let cancelled = false;
        (async () => {
            const stored = await prefsCache.get(PREFS_KEYS.selectedSwayLocaleId);
            if (cancelled) return;
            const id = stored != null ? Number.parseInt(stored, 10) : NaN;
            if (Number.isFinite(id) && id > 0) {
                localeOverride.set(id);
                setSelectedSwayLocaleId(id);
            }
            hydratedRef.current = true;
            void fetchIt();
        })();
        return () => {
            cancelled = true;
        };
    }, [fetchIt]);

    // @lat: [[mobile-bootstrap-lifecycle#Why refetch listens to auth events]]
    useEffect(() => {
        const unsubscribe = authEvents.on((event) => {
            void (async () => {
                // @lat: [[mobile-locale-override-design#Why BootstrapContext clears the choice when the session ends outside sign-out]]
                if (event === "signed_out" || event === "unauthenticated") {
                    setBootstrap(null);
                    localeOverride.clear();
                    (apiClient as { setLocaleId?: (id: number | null) => void }).setLocaleId?.(null);
                    setSelectedSwayLocaleId(null);
                }
                if (event === "unauthenticated") {
                    try {
                        await Promise.all([purgeAll(), bootstrapCache.purge()]);
                    } catch {}
                    try {
                        destroyConsumer();
                    } catch {}
                }
                await fetchIt();
            })();
        });
        return unsubscribe;
    }, [fetchIt]);

    useEffect(() => {
        const sub = AppState.addEventListener("change", (next: AppStateStatus) => {
            if (next !== "active") return;
            const last = lastFetchedRef.current;
            if (last == null || Date.now() - last > STALE_MS) {
                fetchIt();
            }
        });
        return () => {
            (sub as { remove?: () => void } | undefined)?.remove?.();
        };
    }, [fetchIt]);

    const currentVersion = Constants.expoConfig?.version ?? "0.0.0";
    const needsUpdate = !!bootstrap && compareVersion(currentVersion, bootstrap.latest_version) < 0;

    return (
        <BootstrapCtx.Provider
            value={{ bootstrap, loading, error, refetch: fetchIt, selectedSwayLocaleId, needsUpdate }}
        >
            {children}
        </BootstrapCtx.Provider>
    );
}

export function useBootstrap(): BootstrapContextValue {
    const v = useContext(BootstrapCtx);
    if (!v) throw new Error("BootstrapProvider missing — wrap your tree in <BootstrapProvider>");
    return v;
}

function compareVersion(a: string, b: string): number {
    const pa = a.split(".").map((n) => Number(n) || 0);
    const pb = b.split(".").map((n) => Number(n) || 0);
    for (let i = 0; i < 3; i++) {
        const da = pa[i] ?? 0;
        const db = pb[i] ?? 0;
        if (da !== db) return da - db;
    }
    return 0;
}
