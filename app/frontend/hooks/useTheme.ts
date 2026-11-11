import { router, usePage } from "@inertiajs/react";
import { applyThemeFontHref, currentThemeFontHref } from "app/frontend/sway_utils/theme_fonts";
import { isValidThemeId, type ThemeId } from "app/frontend/styles/themes";

// @lat: [[use-theme-server-driven-no-effect#Why "system" and "auto" are different names for the same thing]]
export type ThemeMode = "light" | "system" | "dark";
export type ServerThemeMode = "auto" | "light" | "dark";

const PREFERENCES_PATH = "/users/preferences";

// @lat: [[use-theme-server-driven-no-effect#Why "system" and "auto" are different names for the same thing]]
function toServer(mode: ThemeMode): ServerThemeMode {
    return mode === "system" ? "auto" : mode;
}

// @lat: [[use-theme-server-driven-no-effect#Why "system" and "auto" are different names for the same thing]]
function fromServer(mode: string | undefined | null): ThemeMode {
    if (mode === "auto") return "system";
    if (mode === "light" || mode === "dark") return mode;
    return "light";
}

// @lat: [[use-theme-server-driven-no-effect#Why fromServerId checks against isValidThemeId instead of its own list]]
function fromServerId(id: string | undefined | null): ThemeId {
    return isValidThemeId(id) ? id : "sway";
}

interface ThemeSharedProps {
    // @lat: [[use-theme-server-driven-no-effect#Why font_hrefs stays snake_case]]
    theme?: { preference?: ServerThemeMode; id?: ThemeId; font_hrefs?: Partial<Record<ThemeId, string>> } | null;
    [key: string]: unknown;
}

interface UseThemeResult {
    preference: ThemeMode;
    setPreference: (value: ThemeMode) => void;
    themeId: ThemeId;
    setThemeId: (id: ThemeId) => void;
}

// @lat: [[use-theme-server-driven-no-effect#Why there is no useEffect, useState, or localStorage listener]]
export const useTheme = (): UseThemeResult => {
    const props = usePage<ThemeSharedProps>().props;
    const preference: ThemeMode = fromServer(props.theme?.preference);
    const themeId: ThemeId = fromServerId(props.theme?.id);

    const setPreference = (value: ThemeMode): void => {
        // @lat: [[use-theme-set-theme-id-rollback#Why setPreference protects itself the same way]]
        const serverMode = toServer(preference);
        const hadModeAttr = typeof document !== "undefined" && "themeMode" in document.documentElement.dataset;
        const hadDarkClass = typeof document !== "undefined" && document.documentElement.classList.contains("dark");

        // @lat: [[use-theme-server-driven-no-effect#Why the webfont link is swapped in the same click handler]]
        if (typeof document !== "undefined") {
            const root = document.documentElement;
            root.dataset.themeMode = toServer(value);
            if (value === "dark") {
                root.classList.add("dark");
            } else {
                // @lat: [[use-theme-server-driven-no-effect#Why "system" and "auto" are different names for the same thing]]
                root.classList.remove("dark");
            }
        }

        // @lat: [[use-theme-server-driven-no-effect#Why the PATCH request options are what they are]]
        // @lat: [[partial-reload-poll-lists#Why an empty only list is not a partial request]]
        router.patch(
            PREFERENCES_PATH,
            { preferences: { theme_mode: toServer(value) } },
            {
                preserveState: true,
                preserveScroll: true,
                only: ["theme"],
                onError: () => {
                    // @lat: [[use-theme-set-theme-id-rollback#Why setPreference protects itself the same way]]
                    if (typeof document === "undefined") return;
                    const root = document.documentElement;
                    if (hadModeAttr) {
                        root.dataset.themeMode = serverMode;
                    } else {
                        delete root.dataset.themeMode;
                    }
                    if (hadDarkClass) {
                        root.classList.add("dark");
                    } else {
                        root.classList.remove("dark");
                    }
                },
            },
        );
    };

    // @lat: [[use-theme-set-theme-id-rollback#Why setThemeId exists before anything calls it]]
    const setThemeId = (id: ThemeId): void => {
        // @lat: [[use-theme-set-theme-id-rollback#Why setThemeId exists before anything calls it]]
        const serverThemeId = themeId;
        const hadAttr = typeof document !== "undefined" && "theme" in document.documentElement.dataset;

        // @lat: [[use-theme-server-driven-no-effect#Why the webfont link is swapped in the same click handler]]
        const previousFontHref = currentThemeFontHref();

        if (typeof document !== "undefined") {
            document.documentElement.dataset.theme = id;
            applyThemeFontHref(props.theme?.font_hrefs?.[id]);
        }
        router.patch(
            PREFERENCES_PATH,
            { preferences: { theme_id: id } },
            {
                preserveState: true,
                preserveScroll: true,
                only: ["theme"],
                onError: () => {
                    // @lat: [[use-theme-set-theme-id-rollback#Why setThemeId exists before anything calls it]]
                    if (typeof document === "undefined") return;
                    if (hadAttr) {
                        document.documentElement.dataset.theme = serverThemeId;
                    } else {
                        delete document.documentElement.dataset.theme;
                    }
                    applyThemeFontHref(previousFontHref);
                },
            },
        );
    };

    return { preference, setPreference, themeId, setThemeId };
};
