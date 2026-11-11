// @lat: [[mobile-tab-navigation-architecture#LegislatorsStack and OrgsStack]]
import React from "react";
import { createNativeStackNavigator } from "@react-navigation/native-stack";

import LegislatorsListScreen from "../screens/LegislatorsListScreen";
import LegislatorDetailScreen from "../screens/LegislatorDetailScreen";
import BillDetailScreen from "../screens/BillDetailScreen";
import { useTheme } from "../theme/ThemeProvider";
import { navigatorScreenOptions, pushedScreenOptions } from "./headerOptions";
import type { LegislatorsStackParamList } from "./types";

const Stack = createNativeStackNavigator<LegislatorsStackParamList>();

export default function LegislatorsStack() {
    const { colorScheme } = useTheme();
    return (
        <Stack.Navigator screenOptions={navigatorScreenOptions(colorScheme)}>
            <Stack.Screen name="LegislatorsList" component={LegislatorsListScreen} />
            <Stack.Screen
                name="LegislatorDetail"
                component={LegislatorDetailScreen}
                options={pushedScreenOptions(colorScheme, "Legislators")}
            />
            <Stack.Screen
                name="BillDetail"
                component={BillDetailScreen}
                options={pushedScreenOptions(colorScheme, "Legislator")}
            />
        </Stack.Navigator>
    );
}
