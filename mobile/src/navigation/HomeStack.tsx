// @lat: [[mobile-tab-navigation-architecture#HomeStack and BillsStack share the BillDetail route]]
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import React from "react";

import BillDetailScreen from "../screens/BillDetailScreen";
import BillOfTheMonthScreen from "../screens/BillOfTheMonthScreen";
import { useTheme } from "../theme/ThemeProvider";
import { navigatorScreenOptions, pushedScreenOptions } from "./headerOptions";
import type { HomeStackParamList } from "./types";

const Stack = createNativeStackNavigator<HomeStackParamList>();

export default function HomeStack() {
    const { colorScheme } = useTheme();

    return (
        <Stack.Navigator screenOptions={navigatorScreenOptions(colorScheme)}>
            <Stack.Screen name="BillOfTheMonth" component={BillOfTheMonthScreen} />
            <Stack.Screen
                name="BillDetail"
                component={BillDetailScreen}
                options={pushedScreenOptions(colorScheme, "Home")}
            />
        </Stack.Navigator>
    );
}
