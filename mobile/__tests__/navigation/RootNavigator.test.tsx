import React from "react";
import { fireEvent, render, screen, within } from "@testing-library/react-native";

const mockUseSession = jest.fn();
const mockUseUserProfile = jest.fn();
const mockAppDrawerUnmount = jest.fn();

jest.mock("../../src/hooks/useSession", () => ({ useSession: () => mockUseSession() }));
jest.mock("../../src/hooks/useUserProfile", () => ({ useUserProfile: () => mockUseUserProfile() }));
jest.mock("../../src/navigation/AppDrawer", () => {
    const { useEffect } = require("react");
    const { View } = require("react-native");
    return () => {
        useEffect(() => mockAppDrawerUnmount, []);
        return <View testID="app-drawer" />;
    };
});
jest.mock("../../src/navigation/AuthStack", () => {
    const { View } = require("react-native");
    return () => <View testID="auth-stack" />;
});
jest.mock("../../src/navigation/OnboardingStack", () => {
    const { View } = require("react-native");
    return () => <View testID="onboarding-stack" />;
});

import RootNavigator from "../../src/navigation/RootNavigator";

describe("RootNavigator registration gate", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockUseSession.mockReturnValue({ isAuthenticated: true, loading: false });
        mockUseUserProfile.mockReturnValue({
            user: {
                id: 1,
                address: { street: "100 N Holliday St", city: "Baltimore", region_code: "MD" },
                is_registration_complete: false,
            },
            loading: false,
        });
    });

    // @lat: [[identity-and-access#Registration is asynchronous by necessity]]
    it("keeps a saved address in onboarding until the derived completion field is true", () => {
        render(<RootNavigator />);

        expect(screen.getByTestId("onboarding-stack")).toBeTruthy();
        expect(screen.queryByTestId("app-drawer")).toBeNull();
    });

    it("enters the app drawer when the derived completion field is true", () => {
        mockUseUserProfile.mockReturnValue({
            user: {
                id: 1,
                is_registration_complete: true,
            },
            loading: false,
        });

        render(<RootNavigator />);

        expect(screen.getByTestId("app-drawer")).toBeTruthy();
    });

    it("keeps a missing completion field in onboarding even when the address exists", () => {
        mockUseUserProfile.mockReturnValue({
            user: { id: 1, address: { street: "100 N Holliday St" } },
            loading: false,
        });

        render(<RootNavigator />);

        expect(screen.getByTestId("onboarding-stack")).toBeTruthy();
    });
});

describe("RootNavigator loading state", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockUseUserProfile.mockReturnValue({ user: null, loading: false });
    });

    it("shows the Sway logo and a loading indicator while the session loads", () => {
        mockUseSession.mockReturnValue({ isAuthenticated: false, loading: true });

        render(<RootNavigator />);

        const loading = screen.getByTestId("root-navigator-loading");
        expect(within(loading).getByLabelText("Sway").type).toBe("Image");
        expect(within(loading).getByLabelText("Loading")).toBeTruthy();
    });

    it("keeps the app mounted while a signed-in user's profile refetches", () => {
        const user = { id: 1, is_registration_complete: true };
        mockUseSession.mockReturnValue({ isAuthenticated: true, loading: false });
        mockUseUserProfile.mockReturnValue({ user, loading: false });
        const { rerender } = render(<RootNavigator />);

        mockUseUserProfile.mockReturnValue({ user, loading: true });
        rerender(<RootNavigator />);

        expect(screen.queryByTestId("root-navigator-loading")).toBeNull();
        expect(screen.getByTestId("app-drawer")).toBeTruthy();
        expect(mockAppDrawerUnmount).not.toHaveBeenCalled();
    });

    it("shows the loading screen while a signed-in session loads its first profile", () => {
        mockUseSession.mockReturnValue({ isAuthenticated: true, loading: false });
        mockUseUserProfile.mockReturnValue({ user: null, loading: true });

        render(<RootNavigator />);

        expect(screen.getByTestId("root-navigator-loading")).toBeTruthy();
    });

    // @lat: [[mobile-auth-and-onboarding-flow#RootNavigator]]
    it("offers a retry instead of onboarding when a signed-in profile load finishes with no user", () => {
        const refresh = jest.fn();
        mockUseSession.mockReturnValue({ isAuthenticated: true, loading: false });
        mockUseUserProfile.mockReturnValue({ user: null, loading: false, refresh });

        render(<RootNavigator />);

        expect(screen.getByTestId("root-navigator-load-failed")).toBeTruthy();
        expect(screen.getByText("We could not load your account")).toBeTruthy();
        expect(screen.queryByTestId("onboarding-stack")).toBeNull();
        expect(screen.queryByTestId("root-navigator-loading")).toBeNull();

        fireEvent.press(screen.getByTestId("root-navigator-load-failed-cta"));

        expect(refresh).toHaveBeenCalledTimes(1);
    });

    it("swaps the retry screen for the loading screen while the retry runs", () => {
        mockUseSession.mockReturnValue({ isAuthenticated: true, loading: false });
        mockUseUserProfile.mockReturnValue({ user: null, loading: false, refresh: jest.fn() });
        const { rerender } = render(<RootNavigator />);

        mockUseUserProfile.mockReturnValue({ user: null, loading: true, refresh: jest.fn() });
        rerender(<RootNavigator />);

        expect(screen.queryByTestId("root-navigator-load-failed")).toBeNull();
        expect(screen.getByTestId("root-navigator-loading")).toBeTruthy();
    });

    it("lands on the app drawer when the retry loads a registered user", () => {
        mockUseSession.mockReturnValue({ isAuthenticated: true, loading: false });
        mockUseUserProfile.mockReturnValue({ user: null, loading: false, refresh: jest.fn() });
        const { rerender } = render(<RootNavigator />);

        mockUseUserProfile.mockReturnValue({
            user: { id: 1, is_registration_complete: true },
            loading: false,
            refresh: jest.fn(),
        });
        rerender(<RootNavigator />);

        expect(screen.queryByTestId("root-navigator-load-failed")).toBeNull();
        expect(screen.getByTestId("app-drawer")).toBeTruthy();
    });

    it("shows the sign-in stack, not the retry screen, when signed out", () => {
        mockUseSession.mockReturnValue({ isAuthenticated: false, loading: false });

        render(<RootNavigator />);

        expect(screen.getByTestId("auth-stack")).toBeTruthy();
        expect(screen.queryByTestId("root-navigator-load-failed")).toBeNull();
    });
});
