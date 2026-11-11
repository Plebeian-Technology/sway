import React from "react";
import { StyleSheet } from "react-native";
import { fireEvent, render, screen, within } from "@testing-library/react-native";
import BrandHeader from "../../src/components/BrandHeader";

describe("BrandHeader", () => {
    test("renders an Open menu button that calls onMenuPress once when pressed", () => {
        const onMenuPress = jest.fn();
        render(<BrandHeader title="Bill of the Month" onMenuPress={onMenuPress} />);

        const menuButton = screen.getByRole("button", { name: "Open menu" });
        expect(menuButton.props.testID).toBe("brand-header-menu");

        fireEvent.press(menuButton);
        expect(onMenuPress).toHaveBeenCalledTimes(1);
    });

    test("renders no menu button without onMenuPress", () => {
        render(<BrandHeader title="Bill of the Month" />);

        expect(screen.queryByRole("button", { name: "Open menu" })).toBeNull();
        expect(screen.queryByTestId("brand-header-menu")).toBeNull();
        expect(screen.getByText("Bill of the Month")).toBeTruthy();
    });

    test("makes the title a labelled 44pt button that calls titleAction.onPress", () => {
        const onPress = jest.fn();
        render(<BrandHeader title="All Bills" titleAction={{ onPress, accessibilityLabel: "Back to the top" }} />);

        const titleButton = screen.getByRole("button", { name: "Back to the top" });
        expect(titleButton.props.testID).toBe("brand-header-title-button");
        expect(StyleSheet.flatten(titleButton.props.style).minHeight).toBe(44);
        expect(within(titleButton).getByText("All Bills")).toBeTruthy();

        fireEvent.press(titleButton);
        expect(onPress).toHaveBeenCalledTimes(1);
    });

    test("keeps the title a plain heading without titleAction", () => {
        render(<BrandHeader title="Organizations" onMenuPress={jest.fn()} />);

        expect(screen.queryByTestId("brand-header-title-button")).toBeNull();
        expect(screen.getAllByRole("button")).toHaveLength(1);
        expect(screen.getByRole("header", { name: "Organizations" })).toBeTruthy();
    });
});
