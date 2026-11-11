import React from "react";
import { Text } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { ThemeProvider } from "../../../src/theme/ThemeProvider";
import { Card, CardHeader, CardTitle, CardContent, CardFooter } from "../../../src/components/ui/Card";

const wrap = (ui: React.ReactElement, mode: "light" | "dark" = "light") =>
    render(<ThemeProvider initialMode={mode}>{ui}</ThemeProvider>);

describe("Card (PARITY-03)", () => {
    test("non-interactive Card renders with no accessibilityRole", () => {
        wrap(
            <Card testID="card">
                <Text>hello</Text>
            </Card>,
        );
        const node = screen.getByTestId("card");
        expect(node).toBeTruthy();
        expect(node.props.accessibilityRole).toBeUndefined();
    });

    test("interactive Card sets accessibilityRole=button and label", () => {
        wrap(
            <Card testID="card" onPress={() => {}} accessibilityLabel="Open card">
                <Text>x</Text>
            </Card>,
        );
        const node = screen.getByTestId("card");
        expect(node.props.accessibilityRole).toBe("button");
        expect(node.props.accessibilityLabel).toBe("Open card");
    });

    test("fires onPress exactly once when tapped", () => {
        const onPress = jest.fn();
        wrap(
            <Card testID="card" onPress={onPress} accessibilityLabel="x">
                <Text>x</Text>
            </Card>,
        );
        fireEvent.press(screen.getByTestId("card"));
        expect(onPress).toHaveBeenCalledTimes(1);
    });

    test("light theme — applies shadowBold inline style", () => {
        wrap(
            <Card testID="card" onPress={() => {}} accessibilityLabel="x">
                <Text>x</Text>
            </Card>,
            "light",
        );
        const style = screen.getByTestId("card").props.style;
        // @lat: [[theme-tokens#Theme tokens#Why the mobile app generates its palette from sway.css]]
        expect(style).toEqual(
            expect.arrayContaining([
                expect.objectContaining({ shadowOffset: { width: 0, height: 3 }, shadowOpacity: 0.1, elevation: 3 }),
            ]),
        );
    });

    test("dark theme — renders without crash and shadow present", () => {
        wrap(
            <Card testID="card" onPress={() => {}} accessibilityLabel="x">
                <Text>x</Text>
            </Card>,
            "dark",
        );
        const style = screen.getByTestId("card").props.style;
        expect(style).toEqual(
            expect.arrayContaining([expect.objectContaining({ shadowOffset: { width: 0, height: 2 } })]),
        );
    });

    test("CardTitle is exposed to screen readers as a heading", () => {
        wrap(
            <Card>
                <CardHeader>
                    <CardTitle>Title</CardTitle>
                </CardHeader>
            </Card>,
        );
        expect(screen.getByRole("header", { name: "Title" })).toBeTruthy();
    });

    test("sub-exports render their children", () => {
        wrap(
            <Card testID="card">
                <CardHeader>
                    <CardTitle>Title</CardTitle>
                </CardHeader>
                <CardContent>
                    <Text>Body</Text>
                </CardContent>
                <CardFooter>
                    <Text>Footer</Text>
                </CardFooter>
            </Card>,
        );
        expect(screen.getByText("Title")).toBeTruthy();
        expect(screen.getByText("Body")).toBeTruthy();
        expect(screen.getByText("Footer")).toBeTruthy();
    });
});
