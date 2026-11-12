import React from "react";
import { createNativeStackNavigator } from "@react-navigation/native-stack";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import BillDetailScreen from "../screens/BillDetailScreen";
import FeedScreen from "../screens/FeedScreen";
import { useTheme } from "../theme/ThemeProvider";
import { navigatorScreenOptions, pushedScreenOptions } from "./headerOptions";
import type { FeedStackParamList } from "./types";

const Stack = createNativeStackNavigator<FeedStackParamList>();

export default function FeedStack() {
    const { colorScheme } = useTheme();

    return (
        <Stack.Navigator screenOptions={navigatorScreenOptions(colorScheme)}>
            <Stack.Screen name="FeedList" component={FeedScreen} />
            <Stack.Screen
                name="BillDetail"
                component={BillDetailScreen}
                options={pushedScreenOptions(colorScheme, PARITY_COPY.feed.title)}
            />
        </Stack.Navigator>
    );
}
