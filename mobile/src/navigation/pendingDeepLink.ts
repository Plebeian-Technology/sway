import { useEffect } from "react";
import { Linking } from "react-native";

import { authEvents } from "../auth/authEvents";
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

// @lat: [[mobile-auth-and-onboarding-flow#RootNavigator#A link that arrives before the main screens is kept]]
export const keepLaunchLink = (url: string): string | null => {
    if (mainScreensShowing) return url;
    pendingUrl = url;
    return null;
};

export const discardPendingDeepLink = (): void => {
    pendingUrl = null;
};

// @lat: [[mobile-auth-and-onboarding-flow#RootNavigator#A link that arrives before the main screens is kept]]
export function usePendingDeepLink(mainScreensReady: boolean): void {
    // @lat: [[mobile-auth-and-onboarding-flow#RootNavigator#An expired session keeps the kept link and invite]]
    useEffect(
        () =>
            authEvents.on((event) => {
                if (event !== "signed_out") return;
                pendingUrl = null;
                // @lat: [[mobile-auth-and-onboarding-flow#RootNavigator#Signing out forgets the stored invite]]
                inviteAttribution.clear();
            }),
        [],
    );

    useEffect(() => {
        mainScreensShowing = mainScreensReady;
        if (mainScreensReady && pendingUrl !== null) {
            const url = pendingUrl;
            pendingUrl = null;
            openLink?.(url);
        }
        return () => {
            mainScreensShowing = false;
        };
    }, [mainScreensReady]);
}
