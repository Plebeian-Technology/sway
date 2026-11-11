// @lat: [[mobile-theme-sync-hook#useThemeSync hook]]
import { useCallback } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { useTheme, type ThemeMode } from "../theme/ThemeProvider";

export interface UseThemeSyncResult {
    mode: ThemeMode;
    setMode: (m: ThemeMode) => Promise<void>;
}

export function useThemeSync(): UseThemeSyncResult {
    const { mode, setMode: setLocalMode } = useTheme();

    const setMode = useCallback(
        async (next: ThemeMode) => {
            const prev = mode;
            setLocalMode(next);
            try {
                await apiClient.patch(Routes.userPreferences(), {
                    preferences: { theme_mode: next },
                });
            } catch (err) {
                setLocalMode(prev);
                throw err;
            }
        },
        [mode, setLocalMode],
    );

    return { mode, setMode };
}
