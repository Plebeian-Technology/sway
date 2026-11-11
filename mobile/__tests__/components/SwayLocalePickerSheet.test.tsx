import React from "react";
import { ActionSheetIOS, Platform } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { SwayLocalePickerSheet } from "../../src/components/SwayLocalePickerSheet";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn().mockResolvedValue(undefined),
    ImpactFeedbackStyle: { Light: "light" },
}));

const makeLocale = (id: number, name: string) => ({
    id,
    name,
    city: "",
    region_code: "",
    region_name: "",
    country: "",
    icon_url: "",
    time_zone: "",
    current_session_start_date: "",
});

// @lat: [[locale-name-is-derived#Mobile test formatting fixtures]]
const locales = [makeLocale(1, "baltimore-maryland-united_states"), makeLocale(2, "maryland-united_states")];
const baltimoreFormatted = "Baltimore, Maryland, United States";
const marylandFormatted = "Maryland, United States";

const renderPicker = (onSelect = jest.fn()) =>
    render(
        <ThemeProvider initialMode="light">
            <SwayLocalePickerSheet locales={locales} currentLocale={locales[0]} onSelect={onSelect} />
        </ThemeProvider>,
    );

describe("SwayLocalePickerSheet", () => {
    test("Test 1: renders trigger row with testID locale-picker-trigger", () => {
        renderPicker();
        expect(screen.getByTestId("locale-picker-trigger")).toBeTruthy();
    });

    test("Test 2: trigger row displays currentLocale.name", () => {
        renderPicker();
        expect(screen.getByText(baltimoreFormatted)).toBeTruthy();
    });

    test("Test 3: trigger row has accessibilityRole=button and accessibilityLabel including locale name", () => {
        renderPicker();
        const trigger = screen.getByTestId("locale-picker-trigger");
        expect(trigger.props.accessibilityRole).toBe("button");
        expect(trigger.props.accessibilityLabel).toContain(baltimoreFormatted);
    });

    test("Test 4: trigger row has minHeight 44", () => {
        renderPicker();
        const trigger = screen.getByTestId("locale-picker-trigger");
        const style = trigger.props.style;
        const styles = Array.isArray(style) ? style : [style];
        const hasMinHeight = styles.some(
            (s: unknown) => s && typeof s === "object" && (s as Record<string, unknown>)["minHeight"] === 44,
        );
        expect(hasMinHeight).toBe(true);
    });

    test("Test 5: on iOS, pressing trigger calls ActionSheetIOS.showActionSheetWithOptions with locale names + Cancel", () => {
        // Assigning Platform.OS directly is the normal way React Native tests
        // pretend to be on a given platform
        const originalOS = Platform.OS;
        (Platform as { OS: string }).OS = "ios";
        const spy = jest.spyOn(ActionSheetIOS, "showActionSheetWithOptions").mockImplementation(() => {});

        try {
            const onSelect = jest.fn();
            renderPicker(onSelect);
            fireEvent.press(screen.getByTestId("locale-picker-trigger"));
            expect(spy).toHaveBeenCalledTimes(1);
            const [opts] = spy.mock.calls[0];
            expect(opts.options).toEqual(expect.arrayContaining([baltimoreFormatted, marylandFormatted]));
            expect(opts.cancelButtonIndex).toBe(0);
        } finally {
            (Platform as { OS: string }).OS = originalOS;
            spy.mockRestore();
        }
    });

    test("Test 6: on Android, pressing trigger reveals a Modal with locale options", () => {
        const originalOS = Platform.OS;
        (Platform as { OS: string }).OS = "android";

        try {
            renderPicker();
            fireEvent.press(screen.getByTestId("locale-picker-trigger"));
            expect(screen.getByText(marylandFormatted)).toBeTruthy();
        } finally {
            (Platform as { OS: string }).OS = originalOS;
        }
    });

    test("Test 7: selecting a locale on iOS (index callback) invokes onSelect with the locale id", () => {
        const originalOS = Platform.OS;
        (Platform as { OS: string }).OS = "ios";

        let capturedCallback: ((index: number) => void) | undefined;
        const spy = jest
            .spyOn(ActionSheetIOS, "showActionSheetWithOptions")
            .mockImplementation(
                (
                    _opts: Parameters<typeof ActionSheetIOS.showActionSheetWithOptions>[0],
                    callback: (buttonIndex: number) => void,
                ) => {
                    capturedCallback = callback;
                },
            );

        try {
            const onSelect = jest.fn();
            renderPicker(onSelect);
            fireEvent.press(screen.getByTestId("locale-picker-trigger"));
            // Pretend the user tapped item 1 — the first locale, since Cancel sits at 0
            capturedCallback?.(1);
            expect(onSelect).toHaveBeenCalledWith(1);
        } finally {
            (Platform as { OS: string }).OS = originalOS;
            spy.mockRestore();
        }
    });
});
