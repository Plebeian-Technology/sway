import React from "react";
import { View } from "react-native";
import {
    createDrawerNavigator,
    DrawerContentScrollView,
    DrawerItemList,
    type DrawerContentComponentProps,
} from "@react-navigation/drawer";
import { getFocusedRouteNameFromRoute, type RouteProp } from "@react-navigation/native";
import { Bookmark, FileText, Newspaper, Users, Building2, User } from "lucide-react-native";
import { StatusBar } from "expo-status-bar";
import { SafeAreaView, useSafeAreaInsets } from "react-native-safe-area-context";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { chromeColors } from "../theme/chrome";
import DrawerBrandBlock from "../components/DrawerBrandBlock";
import type { AppDrawerParamList } from "./types";
import FeedStack from "./FeedStack";
import HomeStack from "./HomeStack";
import BillsStack from "./BillsStack";
import LegislatorsStack from "./LegislatorsStack";
import OrgsStack from "./OrgsStack";
import ProfileStack from "./ProfileStack";

// @lat: [[mobile-tab-navigation-architecture#AppDrawer]]
const Drawer = createDrawerNavigator<AppDrawerParamList>();

const TOP_LEVEL_ROUTE_NAMES = [
    "FeedList",
    "BillOfTheMonth",
    "BillsList",
    "PastBillsOfTheMonth",
    "LegislatorsList",
    "OrgsList",
    "ProfileHub",
];

// @lat: [[mobile-tab-navigation-architecture#AppDrawer#Drawer panel padding comes from the root SafeAreaView]]
const DRAWER_CONTENT_SPACING = 12;

// @lat: [[mobile-tab-navigation-architecture#AppDrawer#Edge swipe opens the drawer only on top level screens]]
export const isTopLevelRouteFocused = (route: RouteProp<AppDrawerParamList>): boolean => {
    const focusedRouteName = getFocusedRouteNameFromRoute(route);
    return focusedRouteName === undefined || TOP_LEVEL_ROUTE_NAMES.includes(focusedRouteName);
};

// @lat: [[mobile-chrome-and-scroll-layout#The drawer panel opens with a brand block]]
const renderDrawerContent = (props: DrawerContentComponentProps): React.ReactElement => {
    const focusedRoute = props.state.routes[props.state.index];
    const focusedOptions = props.descriptors[focusedRoute.key]?.options;
    return (
        <DrawerContentScrollView {...props} contentContainerStyle={focusedOptions?.drawerContentContainerStyle}>
            <DrawerBrandBlock />
            <DrawerItemList {...props} />
        </DrawerContentScrollView>
    );
};

const AppDrawer: React.FC = () => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const chrome = chromeColors(colorScheme);
    const insets = useSafeAreaInsets();

    return (
        <View className="flex-1 bg-dominant-light dark:bg-dominant-dark" testID="app-shell">
            {/* @lat: [[mobile-chrome-and-scroll-layout#The brand band runs up under the status bar]] */}
            <StatusBar style="light" />
            <View testID="app-shell-top-inset" style={{ height: insets.top, backgroundColor: chrome.band }} />
            <SafeAreaView
                className="flex-1 bg-dominant-light dark:bg-dominant-dark"
                edges={["left", "right", "bottom"]}
            >
                <Drawer.Navigator
                    initialRouteName="Feed"
                    drawerContent={renderDrawerContent}
                    screenOptions={({ route }) => ({
                        headerShown: false,
                        swipeEnabled: isTopLevelRouteFocused(route),
                        drawerActiveTintColor: t.primaryForeground,
                        drawerActiveBackgroundColor: t.primary,
                        drawerInactiveTintColor: t.foreground,
                        drawerItemStyle: { borderRadius: 12, marginVertical: 2 },
                        overlayColor: t.scrim,
                        drawerStyle: { backgroundColor: t.card },
                        drawerContentContainerStyle: {
                            paddingTop: DRAWER_CONTENT_SPACING,
                            paddingBottom: DRAWER_CONTENT_SPACING,
                            paddingStart: DRAWER_CONTENT_SPACING,
                            paddingEnd: DRAWER_CONTENT_SPACING,
                        },
                        drawerLabelStyle: { fontFamily: "OpenSans-SemiBold", fontSize: 16 },
                        sceneStyle: { backgroundColor: t.background },
                    })}
                >
                    <Drawer.Screen
                        name="Feed"
                        component={FeedStack}
                        options={{
                            drawerLabel: PARITY_COPY.feed.title,
                            drawerItemTestID: "drawer-item-feed",
                            drawerIcon: ({ color, focused }) => (
                                <Newspaper color={color} size={24} strokeWidth={focused ? 2.5 : 2} />
                            ),
                        }}
                    />
                    <Drawer.Screen
                        name="Home"
                        component={HomeStack}
                        options={{
                            drawerLabel: PARITY_COPY.billOfTheMonth.title,
                            drawerItemTestID: "drawer-item-home",
                            drawerIcon: ({ color, focused }) => (
                                <Bookmark color={color} size={24} strokeWidth={focused ? 2.5 : 2} />
                            ),
                        }}
                    />
                    <Drawer.Screen
                        name="Bills"
                        component={BillsStack}
                        options={{
                            drawerLabel: "Bills",
                            drawerItemTestID: "drawer-item-bills",
                            drawerIcon: ({ color, focused }) => (
                                <FileText color={color} size={24} strokeWidth={focused ? 2.5 : 2} />
                            ),
                        }}
                    />
                    <Drawer.Screen
                        name="Legislators"
                        component={LegislatorsStack}
                        options={{
                            drawerLabel: "Legislators",
                            drawerItemTestID: "drawer-item-legislators",
                            drawerIcon: ({ color, focused }) => (
                                <Users color={color} size={24} strokeWidth={focused ? 2.5 : 2} />
                            ),
                        }}
                    />
                    <Drawer.Screen
                        name="Orgs"
                        component={OrgsStack}
                        options={{
                            drawerLabel: "Organizations",
                            drawerItemTestID: "drawer-item-orgs",
                            drawerIcon: ({ color, focused }) => (
                                <Building2 color={color} size={24} strokeWidth={focused ? 2.5 : 2} />
                            ),
                        }}
                    />
                    <Drawer.Screen
                        name="Profile"
                        component={ProfileStack}
                        options={{
                            drawerLabel: "Profile",
                            drawerItemTestID: "drawer-item-profile",
                            drawerIcon: ({ color, focused }) => (
                                <User color={color} size={24} strokeWidth={focused ? 2.5 : 2} />
                            ),
                        }}
                    />
                </Drawer.Navigator>
            </SafeAreaView>
        </View>
    );
};

export default AppDrawer;
