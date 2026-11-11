// @lat: [[mobile-auth-and-onboarding-flow#OnboardingStack]]
import React from "react";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { SafeAreaView } from "react-native-safe-area-context";

import AddressScreen from "../screens/AddressScreen";
import type { OnboardingStackParamList } from "./types";

const Stack = createNativeStackNavigator<OnboardingStackParamList>();

export default function OnboardingStack() {
    return (
        <SafeAreaView
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            edges={["top", "bottom", "left", "right"]}
        >
            <Stack.Navigator screenOptions={{ headerShown: false }}>
                <Stack.Screen name="AddressOnboarding" component={AddressScreen} />
            </Stack.Navigator>
        </SafeAreaView>
    );
}
