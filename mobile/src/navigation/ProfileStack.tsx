// @lat: [[mobile-tab-navigation-architecture#ProfileStack]]
import React from "react";
import { createNativeStackNavigator } from "@react-navigation/native-stack";

import ProfileScreen from "../screens/ProfileScreen";
import AddressScreen from "../screens/AddressScreen";
import NotificationPrefsScreen from "../screens/NotificationPrefsScreen";
import PasskeyManagementScreen from "../screens/PasskeyManagementScreen";
import DeleteAccountScreen from "../screens/DeleteAccountScreen";
import MembershipsListScreen from "../screens/MembershipsListScreen";
import MembershipDetailScreen from "../screens/MembershipDetailScreen";
import MembershipInviteConfirmScreen from "../screens/MembershipInviteConfirmScreen";
import { useTheme } from "../theme/ThemeProvider";
import { navigatorScreenOptions, pushedScreenOptions } from "./headerOptions";
import type { ProfileStackParamList } from "./types";

const Stack = createNativeStackNavigator<ProfileStackParamList>();

export default function ProfileStack() {
    const { colorScheme } = useTheme();
    const fromProfile = pushedScreenOptions(colorScheme, "Profile");
    const fromMemberships = pushedScreenOptions(colorScheme, "Memberships");
    return (
        <Stack.Navigator screenOptions={navigatorScreenOptions(colorScheme)}>
            {/* @lat: [[mobile-tab-navigation-architecture#ProfileStack#Why the main profile screen is named "ProfileHub"]] */}
            <Stack.Screen name="ProfileHub" component={ProfileScreen} />
            <Stack.Screen name="Address" component={AddressScreen} options={fromProfile} />
            <Stack.Screen name="NotificationPrefs" component={NotificationPrefsScreen} options={fromProfile} />
            <Stack.Screen name="PasskeyManagement" component={PasskeyManagementScreen} options={fromProfile} />
            <Stack.Screen name="DeleteAccount" component={DeleteAccountScreen} options={fromProfile} />
            <Stack.Screen name="MembershipsList" component={MembershipsListScreen} options={fromProfile} />
            <Stack.Screen name="MembershipDetail" component={MembershipDetailScreen} options={fromMemberships} />
            <Stack.Screen
                name="MembershipInviteConfirm"
                component={MembershipInviteConfirmScreen}
                options={fromMemberships}
            />
        </Stack.Navigator>
    );
}
