// @lat: [[mobile-admin-area#The admin stack]]
import React from "react";
import { createNativeStackNavigator } from "@react-navigation/native-stack";

import AdminHubScreen from "../screens/admin/AdminHubScreen";
import { useTheme } from "../theme/ThemeProvider";
import { navigatorScreenOptions } from "./headerOptions";
import type { AdminStackParamList } from "./types";

const Stack = createNativeStackNavigator<AdminStackParamList>();

export default function AdminStack() {
    const { colorScheme } = useTheme();
    return (
        <Stack.Navigator screenOptions={navigatorScreenOptions(colorScheme)}>
            <Stack.Screen name="AdminHub" component={AdminHubScreen} />
        </Stack.Navigator>
    );
}
