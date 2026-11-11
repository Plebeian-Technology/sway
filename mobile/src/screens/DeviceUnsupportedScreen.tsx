// @lat: [[mobile-auth-and-onboarding-flow#DeviceUnsupportedScreen]]
import React from "react";
import { Text, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";

import BrandHeader from "../components/BrandHeader";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/Card";
import { Pressable } from "../components/ui/Pressable";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { AuthStackParamList } from "../navigation/types";

type Nav = NativeStackNavigationProp<AuthStackParamList, "DeviceUnsupported">;

export default function DeviceUnsupportedScreen() {
    const nav = useNavigation<Nav>();
    return (
        <View className="flex-1 bg-dominant-light dark:bg-dominant-dark">
            <BrandHeader title="Sway" testID="device-unsupported-brand-header" />
            <View className="flex-1 p-4 justify-center">
                <Card testID="device-unsupported-screen">
                    <CardHeader>
                        <CardTitle>{PARITY_COPY.auth.deviceUnsupported.title}</CardTitle>
                    </CardHeader>
                    <CardContent>
                        <Text className="text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                            {PARITY_COPY.auth.deviceUnsupported.body1}
                        </Text>
                        <Text className="mt-3 text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                            {PARITY_COPY.auth.deviceUnsupported.body2}
                        </Text>
                    </CardContent>
                    <Pressable
                        testID="device-unsupported-cta"
                        variant="outline"
                        onPress={() => nav.navigate("Auth")}
                        accessibilityLabel={PARITY_COPY.auth.deviceUnsupported.cta}
                    >
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            {PARITY_COPY.auth.deviceUnsupported.cta}
                        </Text>
                    </Pressable>
                </Card>
            </View>
        </View>
    );
}
