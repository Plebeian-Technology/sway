import React from "react";
import { render, screen, within } from "@testing-library/react-native";
import { NavigationContainer } from "@react-navigation/native";

let mockUser: Record<string, unknown> = { id: 1 };
jest.mock("../../src/hooks/useUserProfile", () => ({
    useUserProfile: () => ({ user: mockUser, loading: false, refresh: jest.fn() }),
}));

jest.mock("../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

jest.mock("../../src/navigation/FeedStack", () => {
    const { View } = require("react-native");
    return () => <View />;
});
jest.mock("../../src/navigation/HomeStack", () => {
    const { View } = require("react-native");
    return () => <View />;
});
jest.mock("../../src/navigation/BillsStack", () => {
    const { View } = require("react-native");
    return () => <View />;
});
jest.mock("../../src/navigation/LegislatorsStack", () => {
    const { View } = require("react-native");
    return () => <View />;
});
jest.mock("../../src/navigation/OrgsStack", () => {
    const { View } = require("react-native");
    return () => <View />;
});
jest.mock("../../src/navigation/ProfileStack", () => {
    const { View } = require("react-native");
    return () => <View />;
});
jest.mock("../../src/navigation/AdminStack", () => {
    const { View } = require("react-native");
    return () => <View />;
});

import AppDrawer from "../../src/navigation/AppDrawer";

const renderDrawer = () =>
    render(
        <NavigationContainer>
            <AppDrawer />
        </NavigationContainer>,
    );

// @lat: [[mobile-admin-area#The drawer entry]]
describe("AppDrawer admin entry", () => {
    it("shows an Admin item when the user is a Sway admin", () => {
        mockUser = { id: 1, is_sway_admin: true };
        renderDrawer();

        const item = screen.getByTestId("drawer-item-admin", { includeHiddenElements: true });
        expect(within(item).getByText("Admin", { includeHiddenElements: true })).toBeTruthy();
        expect(within(item).getByTestId("lucide-shieldcheck", { includeHiddenElements: true })).toBeTruthy();
    });

    it("shows no Admin item when the profile has no is_sway_admin key", () => {
        mockUser = { id: 1 };
        renderDrawer();

        expect(screen.getByTestId("drawer-item-profile", { includeHiddenElements: true })).toBeTruthy();
        expect(screen.queryByTestId("drawer-item-admin", { includeHiddenElements: true })).toBeNull();
    });
});
