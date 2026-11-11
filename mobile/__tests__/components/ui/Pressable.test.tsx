import React from "react";
import { Text } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { ThemeProvider } from "../../../src/theme/ThemeProvider";
import { Pressable } from "../../../src/components/ui/Pressable";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn().mockResolvedValue(undefined),
    ImpactFeedbackStyle: { Light: "light", Medium: "medium", Heavy: "heavy" },
}));

const wrap = (ui: React.ReactElement, mode: "light" | "dark" = "light") =>
    render(<ThemeProvider initialMode={mode}>{ui}</ThemeProvider>);

describe("Pressable (PARITY-03)", () => {
    test("renders and fires onPress when pressed", () => {
        const onPress = jest.fn();
        wrap(
            <Pressable testID="btn" onPress={onPress} accessibilityLabel="tap">
                <Text>x</Text>
            </Pressable>,
        );
        fireEvent.press(screen.getByTestId("btn"));
        expect(onPress).toHaveBeenCalledTimes(1);
    });

    test("enforces 44pt iOS HIG minimum height", () => {
        wrap(
            <Pressable testID="btn" onPress={() => {}}>
                <Text>x</Text>
            </Pressable>,
        );
        const style = screen.getByTestId("btn").props.style;
        expect(style).toEqual(expect.arrayContaining([expect.objectContaining({ minHeight: 44 })]));
    });

    test("disabled blocks onPress and applies opacity 0.5", () => {
        const onPress = jest.fn();
        wrap(
            <Pressable testID="btn" onPress={onPress} disabled>
                <Text>x</Text>
            </Pressable>,
        );
        const node = screen.getByTestId("btn");
        // Check the disabled state through accessibilityState, which mirrors the
        // native disabled prop, rather than through a condition in our own code.
        expect(node.props.accessibilityState).toEqual(expect.objectContaining({ disabled: true }));
        fireEvent.press(node);
        expect(onPress).not.toHaveBeenCalled();
        const style = node.props.style;
        expect(style).toEqual(expect.arrayContaining([expect.objectContaining({ opacity: 0.5 })]));
    });

    test("destructive variant uses destructive token in className", () => {
        wrap(
            <Pressable testID="btn" onPress={() => {}} variant="destructive">
                <Text>x</Text>
            </Pressable>,
        );
        const cls = screen.getByTestId("btn").props.className;
        expect(cls).toContain("bg-destructive-light");
        expect(cls).toContain("dark:bg-destructive-dark");
    });

    test("ghost variant has bg-transparent and no shadow", () => {
        wrap(
            <Pressable testID="btn" onPress={() => {}} variant="ghost">
                <Text>x</Text>
            </Pressable>,
        );
        const cls = screen.getByTestId("btn").props.className;
        expect(cls).toContain("bg-transparent");
        const style = screen.getByTestId("btn").props.style;
        // @lat: [[theme-tokens#Theme tokens#Why the mobile app generates its palette from sway.css]]
        const hasShadow = (Array.isArray(style) ? style : [style]).some(
            (s) => s && typeof s === "object" && "shadowColor" in s && s.shadowColor === "#000000",
        );
        expect(hasShadow).toBe(false);
    });

    test("light + dark theme render without crash and default variant has shadow", () => {
        const { rerender } = wrap(
            <Pressable testID="btn" onPress={() => {}}>
                <Text>x</Text>
            </Pressable>,
            "light",
        );
        expect(screen.getByTestId("btn")).toBeTruthy();
        rerender(
            <ThemeProvider initialMode="dark">
                <Pressable testID="btn" onPress={() => {}}>
                    <Text>x</Text>
                </Pressable>
            </ThemeProvider>,
        );
        const style = screen.getByTestId("btn").props.style;
        // @lat: [[theme-tokens#Theme tokens#Why the mobile app generates its palette from sway.css]]
        expect(style).toEqual(expect.arrayContaining([expect.objectContaining({ shadowColor: "#000000" })]));
    });

    test("a11y — accessibilityRole=button and label propagate", () => {
        wrap(
            <Pressable testID="btn" onPress={() => {}} accessibilityLabel="Continue">
                <Text>x</Text>
            </Pressable>,
        );
        const node = screen.getByTestId("btn");
        expect(node.props.accessibilityRole).toBe("button");
        expect(node.props.accessibilityLabel).toBe("Continue");
    });
});
