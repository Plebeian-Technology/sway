import React from "react";
import { act, render } from "@testing-library/react-native";
import { Appearance, Text } from "react-native";
import { colorScheme as nativewindColorScheme } from "nativewind";
import { ThemeProvider, useTheme } from "../src/theme/ThemeProvider";

jest.mock("react-native/Libraries/Utilities/useColorScheme", () => ({
    __esModule: true,
    default: () => "dark",
}));

let mockBootstrapThemeMode: string | null = null;
jest.mock("../src/state/BootstrapContext", () => ({
    useBootstrap: () => ({ bootstrap: { current_user: { theme_mode: mockBootstrapThemeMode } } }),
}));

function Consumer() {
    const { colorScheme, mode, setMode } = useTheme();
    return (
        <>
            <Text testID="scheme" onPress={() => setMode("dark")}>
                {colorScheme}
            </Text>
            <Text testID="mode">{mode}</Text>
        </>
    );
}

// @lat: [[theme-token-contract#Mobile's twin: swayTokens#ThemeProvider's theme-mode context]]
describe("ThemeProvider", () => {
    let nativewindSetSpy: jest.SpyInstance;
    let appearanceSetSpy: jest.SpyInstance;

    beforeEach(() => {
        nativewindSetSpy = jest.spyOn(nativewindColorScheme, "set").mockImplementation(() => {});
        appearanceSetSpy = jest.spyOn(Appearance, "setColorScheme").mockImplementation(() => {});
    });

    afterEach(() => {
        jest.restoreAllMocks();
        mockBootstrapThemeMode = null;
    });

    it("defaults colorScheme to a defined string (light or dark)", () => {
        const { getByTestId } = render(
            <ThemeProvider>
                <Consumer />
            </ThemeProvider>,
        );
        const scheme = getByTestId("scheme").props.children;
        expect(["light", "dark"]).toContain(scheme);
    });

    it("setMode('dark') overrides the system color scheme to dark", () => {
        const { getByTestId } = render(
            <ThemeProvider>
                <Consumer />
            </ThemeProvider>,
        );
        act(() => {
            getByTestId("scheme").props.onPress();
        });
        expect(getByTestId("scheme").props.children).toBe("dark");
    });

    it("sets the NativeWind color scheme to light for initialMode light on a dark phone", () => {
        render(
            <ThemeProvider initialMode="light">
                <Consumer />
            </ThemeProvider>,
        );
        expect(nativewindSetSpy).toHaveBeenLastCalledWith("light");
    });

    it("sets the NativeWind color scheme to dark after setMode('dark')", () => {
        const { getByTestId } = render(
            <ThemeProvider initialMode="light">
                <Consumer />
            </ThemeProvider>,
        );
        act(() => {
            getByTestId("scheme").props.onPress();
        });
        expect(nativewindSetSpy).toHaveBeenLastCalledWith("dark");
    });

    it("unpins the app appearance for initialMode auto without setting the NativeWind system scheme", () => {
        render(
            <ThemeProvider initialMode="auto">
                <Consumer />
            </ThemeProvider>,
        );
        expect(appearanceSetSpy).toHaveBeenCalledWith("unspecified");
        expect(nativewindSetSpy).not.toHaveBeenCalledWith("system");
    });

    it("defaults to light mode on a dark phone when no saved mode or initialMode exists", () => {
        const { getByTestId } = render(
            <ThemeProvider>
                <Consumer />
            </ThemeProvider>,
        );
        expect(getByTestId("mode").props.children).toBe("light");
        expect(getByTestId("scheme").props.children).toBe("light");
        expect(nativewindSetSpy).toHaveBeenLastCalledWith("light");
    });

    it("keeps a saved bootstrap theme_mode of dark", () => {
        mockBootstrapThemeMode = "dark";
        const { getByTestId } = render(
            <ThemeProvider>
                <Consumer />
            </ThemeProvider>,
        );
        expect(getByTestId("mode").props.children).toBe("dark");
        expect(getByTestId("scheme").props.children).toBe("dark");
        expect(nativewindSetSpy).toHaveBeenLastCalledWith("dark");
    });

    it("returns to light mode when the saved dark theme_mode goes away on sign-out", () => {
        mockBootstrapThemeMode = "dark";
        const { getByTestId, rerender } = render(
            <ThemeProvider>
                <Consumer />
            </ThemeProvider>,
        );
        expect(getByTestId("mode").props.children).toBe("dark");

        mockBootstrapThemeMode = null;
        rerender(
            <ThemeProvider>
                <Consumer />
            </ThemeProvider>,
        );
        expect(getByTestId("mode").props.children).toBe("light");
        expect(getByTestId("scheme").props.children).toBe("light");
        expect(nativewindSetSpy).toHaveBeenLastCalledWith("light");
    });
});
