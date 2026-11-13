import React from "react";
import { render, screen } from "@testing-library/react-native";
import { NavigationContainer } from "@react-navigation/native";

jest.mock("../../src/screens/BillsListScreen", () => {
    const { Text } = require("react-native");
    return ({ route }: { route: { name: string; params?: { mode?: string } } }) => (
        <Text testID="bills-list-route">{`${route.name}:${route.params?.mode ?? "none"}`}</Text>
    );
});
jest.mock("../../src/screens/BillDetailScreen", () => {
    const { View } = require("react-native");
    return () => <View />;
});

import BillsStack from "../../src/navigation/BillsStack";
import { ThemeProvider } from "../../src/theme/ThemeProvider";

describe("BillsStack", () => {
    // @lat: [[mobile-bills-list-screen#BillsListScreen#Opens on Past Bills of the Month]]
    it("opens on Past Bills of the Month when entered from the drawer", () => {
        render(
            <ThemeProvider>
                <NavigationContainer>
                    <BillsStack />
                </NavigationContainer>
            </ThemeProvider>,
        );

        expect(screen.getByTestId("bills-list-route").props.children).toBe(
            "PastBillsOfTheMonth:past_bills_of_the_month",
        );
    });
});
