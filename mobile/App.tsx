import React, { useEffect, useRef } from "react";
import { NavigationContainer, NavigationContainerRef } from "@react-navigation/native";
import { useFonts } from "expo-font";
import * as SplashScreen from "expo-splash-screen";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider } from "react-native-safe-area-context";
import Constants from "expo-constants";
import GooglePlacesSDK from "react-native-google-places-sdk";

import { ThemeProvider } from "./src/theme/ThemeProvider";
import RootNavigator from "./src/navigation/RootNavigator";
import { linking } from "./src/navigation/linking";
import { BootstrapProvider } from "./src/state/BootstrapContext";
import { DeviceRegistrationProvider } from "./src/state/DeviceRegistrationContext";
import { usePushToken } from "./src/hooks/usePushToken";
import { useDeepLinkRouter } from "./src/hooks/useDeepLinkRouter";
import { UpdateBanner } from "./src/components/UpdateBanner";
import "./global.css";
import { Platform } from "react-native";

SplashScreen.preventAutoHideAsync();

// @lat: [[mobile-expo-config#The Expo config file and the mobile type check#App root provider and font gating]]
function PushWiring({ navRef }: { navRef: React.RefObject<NavigationContainerRef<any> | null> }): null {
    usePushToken();
    useDeepLinkRouter(navRef);
    return null;
}

// @lat: [[mobile-expo-config#The Expo config file and the mobile type check#Why native handover happens in an effect, not at module scope]]
function useGooglePlacesInit(): void {
    useEffect(() => {
        const extra = Constants.expoConfig?.extra as
            | { googlePlacesApiKeyIOS?: string; googlePlacesApiKeyAndroid?: string }
            | undefined;
        const key = Platform.OS === "ios" ? extra?.googlePlacesApiKeyIOS : extra?.googlePlacesApiKeyAndroid;
        if (!key) return;
        try {
            GooglePlacesSDK.initialize(key);
        } catch {
            // @lat: [[mobile-expo-config#The Expo config file and the mobile type check#Why native handover happens in an effect, not at module scope]]
        }
    }, []);
}

export default function App() {
    const [fontsLoaded, fontsError] = useFonts({
        "OpenSans-Light": require("./assets/fonts/OpenSans-Light.ttf"),
        "OpenSans-Regular": require("./assets/fonts/OpenSans-Regular.ttf"),
        "OpenSans-SemiBold": require("./assets/fonts/OpenSans-SemiBold.ttf"),
    });
    const navRef = useRef<NavigationContainerRef<any> | null>(null);
    useGooglePlacesInit();
    const fontsSettled = fontsLoaded || fontsError != null;
    useEffect(() => {
        if (fontsSettled) SplashScreen.hideAsync();
    }, [fontsSettled]);
    if (!fontsSettled) return null;
    return (
        <GestureHandlerRootView style={{ flex: 1 }}>
            <SafeAreaProvider>
                <BootstrapProvider>
                    <ThemeProvider>
                        <DeviceRegistrationProvider>
                            <PushWiring navRef={navRef} />
                            <UpdateBanner />
                            <NavigationContainer ref={navRef} linking={linking}>
                                <RootNavigator />
                            </NavigationContainer>
                        </DeviceRegistrationProvider>
                    </ThemeProvider>
                </BootstrapProvider>
            </SafeAreaProvider>
        </GestureHandlerRootView>
    );
}
