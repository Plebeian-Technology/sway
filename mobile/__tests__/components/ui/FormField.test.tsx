import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { ThemeProvider } from "../../../src/theme/ThemeProvider";
import { FormField } from "../../../src/components/ui/FormField";

const wrap = (ui: React.ReactElement, mode: "light" | "dark" = "light") =>
    render(<ThemeProvider initialMode={mode}>{ui}</ThemeProvider>);

describe("FormField (PARITY-03)", () => {
    test("renders label", () => {
        wrap(<FormField testID="field" label="Email" value="" onChangeText={() => {}} />);
        expect(screen.getByText("Email")).toBeTruthy();
    });

    test("onChangeText fires when input changes", () => {
        const onChangeText = jest.fn();
        wrap(<FormField testID="field" label="Email" value="" onChangeText={onChangeText} />);
        fireEvent.changeText(screen.getByTestId("field-input"), "abc");
        expect(onChangeText).toHaveBeenCalledWith("abc");
    });

    test("renders error text when error prop is provided", () => {
        wrap(
            <FormField testID="field" label="Email" value="" onChangeText={() => {}} error="This field is required." />,
        );
        expect(screen.getByTestId("field-error")).toBeTruthy();
        expect(screen.getByText("This field is required.")).toBeTruthy();
    });

    test("omits error text when error is undefined", () => {
        wrap(<FormField testID="field" label="Email" value="" onChangeText={() => {}} />);
        expect(screen.queryByTestId("field-error")).toBeNull();
    });

    test("disabled input has editable=false and opacity 0.5", () => {
        wrap(<FormField testID="field" label="Email" value="" onChangeText={() => {}} disabled />);
        const input = screen.getByTestId("field-input");
        expect(input.props.editable).toBe(false);
        expect(input.props.style).toEqual(expect.objectContaining({ opacity: 0.5 }));
    });

    test("renders under light and dark theme without crash", () => {
        wrap(<FormField testID="field" label="x" value="" onChangeText={() => {}} />, "light");
        expect(screen.getByTestId("field")).toBeTruthy();
        wrap(<FormField testID="field-dark" label="x" value="" onChangeText={() => {}} />, "dark");
        expect(screen.getByTestId("field-dark")).toBeTruthy();
    });

    test("accessibilityLabel defaults to label prop value", () => {
        wrap(<FormField testID="field" label="Email" value="" onChangeText={() => {}} />);
        const input = screen.getByTestId("field-input");
        expect(input.props.accessibilityLabel).toBe("Email");
    });
});
