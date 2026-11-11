// @lat: [[mobile-auth-and-onboarding-flow#AuthStack]]
import React from "react";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { SafeAreaView } from "react-native-safe-area-context";

import AuthScreen from "../screens/AuthScreen";
import DeviceUnsupportedScreen from "../screens/DeviceUnsupportedScreen";
import type { AuthStackParamList } from "./types";

const Stack = createNativeStackNavigator<AuthStackParamList>();

export default function AuthStack() {
    return (
        <SafeAreaView
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            edges={["top", "bottom", "left", "right"]}
        >
            <Stack.Navigator screenOptions={{ headerShown: false }}>
                <Stack.Screen name="Auth" component={AuthScreen} />
                <Stack.Screen name="DeviceUnsupported" component={DeviceUnsupportedScreen} />
            </Stack.Navigator>
        </SafeAreaView>
    );
}
