// @lat: [[mobile-jest-first-pass-test-notes#AuthScreen.test.tsx / DeviceUnsupportedScreen.test.tsx]]
import React from "react";
import { render, fireEvent, waitFor } from "@testing-library/react-native";

import DeviceUnsupportedScreen from "../../src/screens/DeviceUnsupportedScreen";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const mockNavigate = jest.fn();
jest.mock("@react-navigation/native", () => ({
    ...jest.requireActual("@react-navigation/native"),
    useNavigation: () => ({ navigate: mockNavigate }),
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

beforeEach(() => mockNavigate.mockClear());

describe("DeviceUnsupportedScreen", () => {
    test("renders Card with all 4 copy strings from PARITY_COPY.auth.deviceUnsupported", () => {
        const { getByTestId, getByText } = wrap(<DeviceUnsupportedScreen />);

        expect(getByTestId("device-unsupported-screen")).toBeTruthy();

        expect(getByText(PARITY_COPY.auth.deviceUnsupported.title)).toBeTruthy();
        expect(getByText(PARITY_COPY.auth.deviceUnsupported.body1)).toBeTruthy();
        expect(getByText(PARITY_COPY.auth.deviceUnsupported.body2)).toBeTruthy();
        expect(getByText(PARITY_COPY.auth.deviceUnsupported.cta)).toBeTruthy();
    });

    test("navigates to 'Auth' (not 'SignIn') on CTA press — fixes Pitfall 1 nav-target bug", async () => {
        const { getByTestId } = wrap(<DeviceUnsupportedScreen />);

        fireEvent.press(getByTestId("device-unsupported-cta"));

        await waitFor(() => expect(mockNavigate).toHaveBeenCalledWith("Auth"));

        // The old route name "SignIn" must never be used again.
        expect(mockNavigate).not.toHaveBeenCalledWith("SignIn");
    });

    test("CTA Pressable carries accessibilityLabel matching CTA copy", () => {
        const { getByLabelText } = wrap(<DeviceUnsupportedScreen />);

        expect(getByLabelText(PARITY_COPY.auth.deviceUnsupported.cta)).toBeTruthy();
    });
});
