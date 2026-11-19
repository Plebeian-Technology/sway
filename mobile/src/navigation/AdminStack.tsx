// @lat: [[mobile-admin-area#The admin stack]]
import React from "react";
import { createNativeStackNavigator } from "@react-navigation/native-stack";

import AdminHubScreen from "../screens/admin/AdminHubScreen";
import BillSummaryReportScreen from "../screens/admin/BillSummaryReportScreen";
import BillSummaryReportsScreen from "../screens/admin/BillSummaryReportsScreen";
import CategoriesScreen from "../screens/admin/CategoriesScreen";
import LlmSettingsScreen from "../screens/admin/LlmSettingsScreen";
import LocalesScreen from "../screens/admin/LocalesScreen";
import PartnerReportScreen from "../screens/admin/PartnerReportScreen";
import PartnerReportsScreen from "../screens/admin/PartnerReportsScreen";
import PipelineRunsScreen from "../screens/admin/PipelineRunsScreen";
import RegistrationFunnelScreen from "../screens/admin/RegistrationFunnelScreen";
import SharedAddressesScreen from "../screens/admin/SharedAddressesScreen";
import SystemPromptsScreen from "../screens/admin/SystemPromptsScreen";
import UserAddressChangesScreen from "../screens/admin/UserAddressChangesScreen";
import { useTheme } from "../theme/ThemeProvider";
import { navigatorScreenOptions, pushedScreenOptions } from "./headerOptions";
import type { AdminStackParamList } from "./types";

const Stack = createNativeStackNavigator<AdminStackParamList>();

export default function AdminStack() {
    const { colorScheme } = useTheme();
    const fromHub = pushedScreenOptions(colorScheme, "Admin");
    return (
        <Stack.Navigator screenOptions={navigatorScreenOptions(colorScheme)}>
            <Stack.Screen name="AdminHub" component={AdminHubScreen} />
            <Stack.Screen name="AdminSharedAddresses" component={SharedAddressesScreen} options={fromHub} />
            <Stack.Screen name="AdminUserAddressChanges" component={UserAddressChangesScreen} options={fromHub} />
            <Stack.Screen name="AdminSystemPrompts" component={SystemPromptsScreen} options={fromHub} />
            <Stack.Screen name="AdminLocales" component={LocalesScreen} options={fromHub} />
            <Stack.Screen name="AdminCategories" component={CategoriesScreen} options={fromHub} />
            <Stack.Screen name="AdminLlmSettings" component={LlmSettingsScreen} options={fromHub} />
            <Stack.Screen name="AdminBillSummaryReports" component={BillSummaryReportsScreen} options={fromHub} />
            <Stack.Screen
                name="AdminBillSummaryReport"
                component={BillSummaryReportScreen}
                options={pushedScreenOptions(colorScheme, "Reports")}
            />
            <Stack.Screen name="AdminPartnerReports" component={PartnerReportsScreen} options={fromHub} />
            <Stack.Screen
                name="AdminPartnerReport"
                component={PartnerReportScreen}
                options={pushedScreenOptions(colorScheme, "Partners")}
            />
            <Stack.Screen name="AdminRegistrationFunnel" component={RegistrationFunnelScreen} options={fromHub} />
            <Stack.Screen name="AdminPipelineRuns" component={PipelineRunsScreen} options={fromHub} />
        </Stack.Navigator>
    );
}
