import { useEffect, useRef } from "react";
import { Linking } from "react-native";

import { inviteAttribution } from "../state/inviteAttribution";

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

export const discardPendingDeepLink = (): void => {
    pendingUrl = null;
};

// @lat: [[mobile-auth-and-onboarding-flow#RootNavigator#A link that arrives before the main screens is kept]]
export function usePendingDeepLink(mainScreensReady: boolean, isAuthenticated: boolean): void {
    const wasAuthenticated = useRef(isAuthenticated);

    useEffect(() => {
        if (!isAuthenticated) pendingUrl = null;
        // @lat: [[mobile-auth-and-onboarding-flow#RootNavigator#Signing out forgets the stored invite]]
        if (wasAuthenticated.current && !isAuthenticated) inviteAttribution.clear();
        wasAuthenticated.current = isAuthenticated;
    }, [isAuthenticated]);

    useEffect(() => {
        mainScreensShowing = mainScreensReady;
        if (!mainScreensReady || pendingUrl === null) return;

        const url = pendingUrl;
        pendingUrl = null;
        openLink?.(url);
    }, [mainScreensReady]);
}
