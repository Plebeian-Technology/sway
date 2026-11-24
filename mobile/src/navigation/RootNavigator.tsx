// @lat: [[mobile-auth-and-onboarding-flow#RootNavigator]]
import React from "react";
import { View } from "react-native";

import AppDrawer from "./AppDrawer";
import AuthStack from "./AuthStack";
import OnboardingStack from "./OnboardingStack";
import { usePendingDeepLink } from "./pendingDeepLink";
import { useSession } from "../hooks/useSession";
import { useUserProfile } from "../hooks/useUserProfile";
import { EmptyState } from "../components/ui/EmptyState";
import LoadingScreen from "../screens/LoadingScreen";

export default function RootNavigator() {
    const { isAuthenticated, loading: sessionLoading } = useSession();
    const { user, loading: userLoading, refresh } = useUserProfile();
    const mainScreensReady = !sessionLoading && isAuthenticated && user?.is_registration_complete === true;
    usePendingDeepLink(mainScreensReady, isAuthenticated);

    if (sessionLoading || (isAuthenticated && userLoading && user === null)) {
        return <LoadingScreen testID="root-navigator-loading" />;
    }
    if (!isAuthenticated) {
        return <AuthStack />;
    }
    if (user === null) {
        return (
            <View className="flex-1 items-center justify-center bg-dominant-light dark:bg-dominant-dark">
                <EmptyState
                    testID="root-navigator-load-failed"
                    title="We could not load your account"
                    body="Check your connection and try again."
                    ctaLabel="Try again"
                    onCtaPress={() => void refresh()}
                />
            </View>
        );
    }
    // @lat: [[identity-and-access#Registration is asynchronous by necessity]]
    if (user.is_registration_complete !== true) {
        return <OnboardingStack />;
    }
    return <AppDrawer />;
}
