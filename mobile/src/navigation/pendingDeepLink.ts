import { useEffect } from "react";
import { Linking } from "react-native";

type OpenLink = (url: string) => void;

let openLink: OpenLink | null = null;
let mainScreensShowing = false;
let pendingUrl: string | null = null;

// @lat: [[mobile-auth-and-onboarding-flow#RootNavigator#A link that arrives before the main screens is kept]]
export const subscribeToLinks = (listener: OpenLink): (() => void) => {
    openLink = listener;
    const subscription = Linking.addEventListener("url", ({ url }) => {
        if (!mainScreensShowing) pendingUrl = url;
        listener(url);
    });
    return () => {
        openLink = null;
        subscription.remove();
    };
};

// @lat: [[mobile-auth-and-onboarding-flow#RootNavigator#A link that arrives before the main screens is kept]]
export function usePendingDeepLink(mainScreensReady: boolean, isAuthenticated: boolean): void {
    useEffect(() => {
        if (!isAuthenticated) pendingUrl = null;
    }, [isAuthenticated]);

    useEffect(() => {
        mainScreensShowing = mainScreensReady;
        if (!mainScreensReady || pendingUrl === null) return;

        const url = pendingUrl;
        pendingUrl = null;
        openLink?.(url);
    }, [mainScreensReady]);
}
