import React, { createContext, useContext, useEffect, useMemo, useState } from "react";
import { Appearance, useColorScheme } from "react-native";
import { colorScheme as nativewindColorScheme } from "nativewind";

// @lat: [[theme-token-contract#Mobile's twin: swayTokens#ThemeProvider's theme-mode context]]
export type ThemeMode = "auto" | "light" | "dark";

interface ThemeContextValue {
    colorScheme: "light" | "dark";
    mode: ThemeMode;
    setMode: (m: ThemeMode) => void;
}

// @lat: [[theme-token-contract#Mobile's twin: swayTokens#ThemeProvider's theme-mode context]]
const DEFAULT_THEME_VALUE: ThemeContextValue = {
    colorScheme: "light",
    mode: "light",
    setMode: () => {},
};

const ThemeContext = createContext<ThemeContextValue>(DEFAULT_THEME_VALUE);

export function useTheme(): ThemeContextValue {
    return useContext(ThemeContext);
}

// @lat: [[theme-token-contract#Mobile's twin: swayTokens#ThemeProvider's theme-mode context]]
function readBootstrapModeSafely(): ThemeMode | null {
    try {
        // oxlint-disable-next-line @typescript-eslint/no-require-imports
        const mod: { useBootstrap?: () => unknown } = require("../state/BootstrapContext");
        if (typeof mod.useBootstrap !== "function") return null;
        const ctx = mod.useBootstrap() as
            | { bootstrap?: { current_user?: { theme_mode?: string | null } | null } | null }
            | null
            | undefined;
        const tm = ctx?.bootstrap?.current_user?.theme_mode;
        if (tm === "auto" || tm === "light" || tm === "dark") return tm;
        return null;
    } catch {
        return null;
    }
}

export interface ThemeProviderProps {
    children: React.ReactNode;
    initialMode?: ThemeMode;
}

export function ThemeProvider({ children, initialMode }: ThemeProviderProps) {
    // @lat: [[theme-token-contract#Mobile's twin: swayTokens#ThemeProvider's theme-mode context]]
    const raw = useColorScheme();
    const system: "light" | "dark" = raw === "dark" ? "dark" : "light";

    const bootstrapMode = readBootstrapModeSafely();
    const [mode, setMode] = useState<ThemeMode>(bootstrapMode ?? initialMode ?? "light");

    // @lat: [[theme-token-contract#Mobile's twin: swayTokens#ThemeProvider's theme-mode context]]
    useEffect(() => {
        const next = bootstrapMode ?? initialMode ?? "light";
        if (next !== mode) {
            setMode(next);
        }
        // oxlint-disable-next-line react-hooks/exhaustive-deps
    }, [bootstrapMode]);

    // @lat: [[theme-token-contract#Mobile's twin: swayTokens#ThemeProvider's theme-mode context]]
    useEffect(() => {
        if (mode === "auto") {
            Appearance.setColorScheme("unspecified");
        } else {
            nativewindColorScheme.set(mode);
        }
    }, [mode]);

    const colorScheme: "light" | "dark" = mode === "auto" ? system : mode;
    const value = useMemo<ThemeContextValue>(() => ({ colorScheme, mode, setMode }), [colorScheme, mode]);
    return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}
