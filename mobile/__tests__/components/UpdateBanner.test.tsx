// @lat: [[mobile-jest-first-pass-test-notes#UpdateBanner.test.tsx]]

let mockNeedsUpdate = true;
jest.mock("../../src/state/BootstrapContext", () => ({
    useBootstrap: () => ({
        bootstrap: null,
        loading: false,
        error: null,
        refetch: jest.fn(),
        needsUpdate: mockNeedsUpdate,
    }),
}));

// Watch React Native's Linking.openURL after importing it. Reaching for
// jest.mock("react-native", ...) instead breaks React Native under jest-expo,
// because its modules import each other in a loop.
const mockOpenURL = jest.fn(async (_url: string) => true);

// jest.setup already fakes lucide-react-native in a general way, but it does not
// list the X icon UpdateBanner uses, so add that one here as a plain View.
jest.mock("lucide-react-native", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    const RNMod = require("react-native");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    return {
        X: function XStub() {
            return ReactMod.createElement(RNMod.View, { testID: "lucide-x" });
        },
    };
});

import React from "react";
import { Linking } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { UpdateBanner } from "../../src/components/UpdateBanner";

describe("UpdateBanner", () => {
    beforeEach(() => {
        mockNeedsUpdate = true;
        mockOpenURL.mockClear();
        jest.spyOn(Linking, "openURL").mockImplementation((url: string) => mockOpenURL(url));
    });

    afterEach(() => {
        (Linking.openURL as jest.Mock).mockRestore?.();
    });

    test("renders 'A new version of Sway is available.' when needsUpdate is true", () => {
        render(<UpdateBanner />);
        expect(screen.getByText("A new version of Sway is available.")).toBeTruthy();
    });

    test("renders the Update link with accessibilityRole=link", () => {
        render(<UpdateBanner />);
        expect(screen.getByLabelText("Update")).toBeTruthy();
    });

    test("renders dismiss button with accessibilityLabel='Dismiss update banner'", () => {
        render(<UpdateBanner />);
        expect(screen.getByLabelText("Dismiss update banner")).toBeTruthy();
    });

    test("returns null when needsUpdate is false", () => {
        mockNeedsUpdate = false;
        const { toJSON } = render(<UpdateBanner />);
        expect(toJSON()).toBeNull();
    });

    test("dismiss button hides the banner", () => {
        render(<UpdateBanner />);
        expect(screen.queryByText("A new version of Sway is available.")).toBeTruthy();
        fireEvent.press(screen.getByLabelText("Dismiss update banner"));
        expect(screen.queryByText("A new version of Sway is available.")).toBeNull();
    });

    test("Update link opens the download URL via Linking.openURL", () => {
        render(<UpdateBanner />);
        fireEvent.press(screen.getByLabelText("Update"));
        expect(mockOpenURL).toHaveBeenCalledWith("https://sway.vote/download");
    });
});
