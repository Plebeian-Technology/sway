// @lat: [[mobile-auth-and-onboarding-flow#RootNavigator]]
import React from "react";

import AppDrawer from "./AppDrawer";
import AuthStack from "./AuthStack";
import OnboardingStack from "./OnboardingStack";
import { useSession } from "../hooks/useSession";
import { useUserProfile } from "../hooks/useUserProfile";
import LoadingScreen from "../screens/LoadingScreen";

export default function RootNavigator() {
    const { isAuthenticated, loading: sessionLoading } = useSession();
    const { user, loading: userLoading } = useUserProfile();

    if (sessionLoading || (isAuthenticated && userLoading && user === null)) {
        return <LoadingScreen testID="root-navigator-loading" />;
    }
    if (!isAuthenticated) {
        return <AuthStack />;
    }
    // @lat: [[identity-and-access#Registration is asynchronous by necessity]]
    if (user?.is_registration_complete !== true) {
        return <OnboardingStack />;
    }
    return <AppDrawer />;
}
