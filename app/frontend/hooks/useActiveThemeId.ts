import { useSyncExternalStore } from "react";

import { isValidThemeId, type ThemeId } from "app/frontend/styles/themes";

// @lat: [[use-active-theme-id-sync-external-store#Why useSyncExternalStore, not useEffect + useState]]

function subscribe(onStoreChange: () => void): () => void {
    if (typeof document === "undefined") {
        return () => {};
    }

    const observer = new MutationObserver(onStoreChange);
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
    return () => observer.disconnect();
}

function getSnapshot(): ThemeId {
    const id = typeof document === "undefined" ? undefined : document.documentElement.dataset.theme;
    return isValidThemeId(id) ? id : "sway";
}

function getServerSnapshot(): ThemeId {
    return "sway";
}

export const useActiveThemeId = (): ThemeId => {
    return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
};
