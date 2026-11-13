import React from "react";
import { render, screen, waitFor, within } from "@testing-library/react-native";

// @lat: [[mobile-jest-first-pass-test-notes#App test supplies the completed profile contract]]
jest.mock("../src/hooks/useSession", () => ({
    useSession: () => ({
        isAuthenticated: true,
        loading: false,
        signOut: jest.fn(),
        signOutAll: jest.fn(),
    }),
}));

// @lat: [[mobile-jest-first-pass-test-notes#App test supplies the completed profile contract]]
jest.mock("../src/hooks/useUserProfile", () => ({
    useUserProfile: () => ({
        user: {
            id: 1,
            phone: "+15555550100",
            // @lat: [[mobile-jest-first-pass-test-notes#App test supplies the completed profile contract]]
            address: {
                street1: "1 Main St",
                city: "Baltimore",
                region_code: "MD",
                postal_code: "21201",
                country: "United States",
            },
            is_registration_complete: true,
            registration_status: "completed",
        },
        loading: false,
        refresh: jest.fn(),
    }),
}));

let mockFontsLoaded = true;
let mockFontsError: Error | null = null;
jest.mock("expo-font", () => ({
    useFonts: () => [mockFontsLoaded, mockFontsError],
    isLoaded: jest.fn(() => true),
}));

jest.mock("expo-splash-screen", () => ({
    preventAutoHideAsync: jest.fn(async () => true),
    hideAsync: jest.fn(async () => {}),
}));

import * as SplashScreen from "expo-splash-screen";
import App from "../App";

// @lat: [[mobile-jest-first-pass-test-notes#App test has a bounded navigator render]]
const RENDER_BOUND_TIMEOUT_MS = 30_000;

const originalFetch = global.fetch;

describe("App", () => {
    // @lat: [[mobile-jest-first-pass-test-notes#App test never reaches the network]]
    beforeEach(() => {
        global.fetch = jest.fn().mockRejectedValue(new TypeError("Network request failed")) as unknown as typeof fetch;
    });

    afterEach(() => {
        global.fetch = originalFetch;
    });

    it(
        "renders the drawer with its 6 items and a menu button",
        async () => {
            render(<App />);
            // @lat: [[mobile-jest-first-pass-test-notes#App test supplies the completed profile contract]]
            await waitFor(() => expect(screen.getByLabelText("Open menu")).toBeTruthy());
            const drawerItems = [
                ["drawer-item-feed", "Feed"],
                ["drawer-item-home", "Bill of the Month"],
                ["drawer-item-bills", "Bills"],
                ["drawer-item-legislators", "Legislators"],
                ["drawer-item-orgs", "Organizations"],
                ["drawer-item-profile", "Profile"],
            ] as const;
            for (const [testId, label] of drawerItems) {
                const drawerItem = screen.getByTestId(testId, { includeHiddenElements: true });
                expect(within(drawerItem).getByText(label, { includeHiddenElements: true })).toBeTruthy();
            }
            // @lat: [[mobile-tab-navigation-architecture#AppDrawer#The drawer opens on Feed]]
            expect(
                screen.getByTestId("drawer-item-feed", { includeHiddenElements: true }).props.accessibilityState,
            ).toEqual(expect.objectContaining({ selected: true }));
        },
        RENDER_BOUND_TIMEOUT_MS,
    );

    it("holds the native splash screen from module load, before any render", () => {
        jest.isolateModules(() => {
            const isolatedSplash = require("expo-splash-screen") as typeof SplashScreen;
            jest.mocked(isolatedSplash.preventAutoHideAsync).mockClear();

            require("../App");

            expect(isolatedSplash.preventAutoHideAsync).toHaveBeenCalledTimes(1);
        });
    });

    it(
        "hides the native splash screen once fonts load, not before",
        async () => {
            jest.mocked(SplashScreen.hideAsync).mockClear();
            mockFontsLoaded = false;
            const { rerender } = render(<App />);
            expect(SplashScreen.hideAsync).not.toHaveBeenCalled();

            mockFontsLoaded = true;
            rerender(<App />);
            await waitFor(() => expect(SplashScreen.hideAsync).toHaveBeenCalledTimes(1));
        },
        RENDER_BOUND_TIMEOUT_MS,
    );

    it(
        "hides the native splash screen and renders the app when fonts fail to load",
        async () => {
            jest.mocked(SplashScreen.hideAsync).mockClear();
            mockFontsLoaded = false;
            mockFontsError = new Error("font failed to load");
            try {
                render(<App />);
                await waitFor(() => expect(SplashScreen.hideAsync).toHaveBeenCalledTimes(1));
                await waitFor(() => expect(screen.getByLabelText("Open menu")).toBeTruthy());
            } finally {
                mockFontsLoaded = true;
                mockFontsError = null;
            }
        },
        RENDER_BOUND_TIMEOUT_MS,
    );
});
