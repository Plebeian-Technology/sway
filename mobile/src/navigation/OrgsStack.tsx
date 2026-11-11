// @lat: [[mobile-tab-navigation-architecture#LegislatorsStack and OrgsStack]]
import React from "react";
import { createNativeStackNavigator } from "@react-navigation/native-stack";

import OrgsListScreen from "../screens/OrgsListScreen";
import OrgDetailScreen from "../screens/OrgDetailScreen";
import { useTheme } from "../theme/ThemeProvider";
import { navigatorScreenOptions, pushedScreenOptions } from "./headerOptions";
import type { OrgsStackParamList } from "./types";

const Stack = createNativeStackNavigator<OrgsStackParamList>();

export default function OrgsStack() {
    const { colorScheme } = useTheme();
    return (
        <Stack.Navigator screenOptions={navigatorScreenOptions(colorScheme)}>
            <Stack.Screen name="OrgsList" component={OrgsListScreen} />
            <Stack.Screen
                name="OrgDetail"
                component={OrgDetailScreen}
                options={pushedScreenOptions(colorScheme, "Organizations")}
            />
        </Stack.Navigator>
    );
}
