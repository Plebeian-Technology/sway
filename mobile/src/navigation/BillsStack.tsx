// @lat: [[mobile-tab-navigation-architecture#HomeStack and BillsStack share the BillDetail route]]
import React from "react";
import { createNativeStackNavigator } from "@react-navigation/native-stack";

import BillsListScreen from "../screens/BillsListScreen";
import BillDetailScreen from "../screens/BillDetailScreen";
import { useTheme } from "../theme/ThemeProvider";
import { navigatorScreenOptions, pushedScreenOptions } from "./headerOptions";
import type { BillsStackParamList } from "./types";

const Stack = createNativeStackNavigator<BillsStackParamList>();

export default function BillsStack() {
    const { colorScheme } = useTheme();
    return (
        <Stack.Navigator initialRouteName="PastBillsOfTheMonth" screenOptions={navigatorScreenOptions(colorScheme)}>
            <Stack.Screen name="BillsList" component={BillsListScreen} />
            <Stack.Screen
                name="PastBillsOfTheMonth"
                component={BillsListScreen}
                initialParams={{ mode: "past_bills_of_the_month" }}
            />
            <Stack.Screen
                name="BillDetail"
                component={BillDetailScreen}
                options={pushedScreenOptions(colorScheme, "Bills")}
            />
        </Stack.Navigator>
    );
}
