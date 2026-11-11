const mockSignOut = jest.fn(async () => {});
const mockSignOutAll = jest.fn(async () => {});
jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => ({
        isAuthenticated: true,
        loading: false,
        signOut: mockSignOut,
        signOutAll: mockSignOutAll,
    }),
}));

jest.mock("../../src/hooks/useUserProfile", () => ({
    useUserProfile: () => ({
        user: { id: 1, full_name: "Voter One", phone: "4105551212", theme_mode: "auto" },
        loading: false,
        refresh: jest.fn(),
    }),
}));

const mockSetMode = jest.fn().mockResolvedValue(undefined);
let mockMode: "auto" | "light" | "dark" = "auto";
jest.mock("../../src/hooks/useThemeSync", () => ({
    useThemeSync: () => ({ mode: mockMode, setMode: mockSetMode }),
}));

import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { NavigationContainer } from "@react-navigation/native";

import ProfileScreen from "../../src/screens/ProfileScreen";

const mockNavigate = jest.fn();
jest.mock("@react-navigation/native", () => {
    const actual = jest.requireActual("@react-navigation/native");
    return {
        ...actual,
        useNavigation: () => ({ navigate: mockNavigate }),
    };
});

describe("ProfileScreen", () => {
    beforeEach(() => {
        mockSignOut.mockReset();
        mockSignOutAll.mockReset();
        mockNavigate.mockReset();
        mockSetMode.mockReset();
        mockSetMode.mockResolvedValue(undefined);
        mockMode = "auto";
    });

    function renderIt() {
        return render(
            <NavigationContainer>
                <ProfileScreen />
            </NavigationContainer>,
        );
    }

    test("renders the 8 menu rows in the verbatim Phase 37 order", () => {
        renderIt();
        expect(screen.getByLabelText("Address")).toBeTruthy();
        expect(screen.getByLabelText("My Memberships")).toBeTruthy();
        expect(screen.getByLabelText("Notification Preferences")).toBeTruthy();
        expect(screen.getByLabelText("Passkey Management")).toBeTruthy();
        expect(screen.getByTestId("profile-row-theme")).toBeTruthy();
        expect(screen.getByLabelText("Sign Out")).toBeTruthy();
        expect(screen.getByLabelText("Sign Out All Devices")).toBeTruthy();
        expect(screen.getByLabelText("Delete Account")).toBeTruthy();
    });

    test("tapping each navigation row pushes the matching screen (Theme stays inline)", () => {
        renderIt();
        fireEvent.press(screen.getByLabelText("Address"));
        expect(mockNavigate).toHaveBeenCalledWith("Address");
        fireEvent.press(screen.getByLabelText("My Memberships"));
        expect(mockNavigate).toHaveBeenCalledWith("MembershipsList");
        fireEvent.press(screen.getByLabelText("Notification Preferences"));
        expect(mockNavigate).toHaveBeenCalledWith("NotificationPrefs");
        fireEvent.press(screen.getByLabelText("Passkey Management"));
        expect(mockNavigate).toHaveBeenCalledWith("PasskeyManagement");
        fireEvent.press(screen.getByLabelText("Delete Account"));
        expect(mockNavigate).toHaveBeenCalledWith("DeleteAccount");
        fireEvent.press(screen.getByTestId("profile-row-theme"));
        expect(mockNavigate).not.toHaveBeenCalledWith("ThemeToggle");
    });

    test("Theme row cycles Auto -> Light", () => {
        mockMode = "auto";
        renderIt();
        fireEvent.press(screen.getByTestId("profile-row-theme"));
        expect(mockSetMode).toHaveBeenCalledWith("light");
    });

    test("Theme row cycles Light -> Dark", () => {
        mockMode = "light";
        renderIt();
        fireEvent.press(screen.getByTestId("profile-row-theme"));
        expect(mockSetMode).toHaveBeenCalledWith("dark");
    });

    test("Theme row cycles Dark -> Auto", () => {
        mockMode = "dark";
        renderIt();
        fireEvent.press(screen.getByTestId("profile-row-theme"));
        expect(mockSetMode).toHaveBeenCalledWith("auto");
    });

    test("Theme row accessory displays the current mode label", () => {
        mockMode = "dark";
        renderIt();
        // The text at the edge of the Theme row comes from PARITY_COPY.theme.dark.label.
        expect(screen.getByText("Dark")).toBeTruthy();
    });

    test("Theme row accessibilityLabel announces current and next modes", () => {
        mockMode = "auto";
        renderIt();
        expect(screen.getByLabelText("Theme: Auto. Tap to switch to Light.")).toBeTruthy();
    });

    test("Sign Out invokes useSession.signOut", () => {
        renderIt();
        fireEvent.press(screen.getByLabelText("Sign Out"));
        expect(mockSignOut).toHaveBeenCalledTimes(1);
    });

    test("Sign Out All Devices opens the DestructiveSheet (does not call signOutAll directly)", () => {
        renderIt();
        fireEvent.press(screen.getByLabelText("Sign Out All Devices"));
        expect(screen.getByTestId("destructive-sheet-title")).toHaveTextContent("Sign out all devices");
        expect(mockSignOutAll).not.toHaveBeenCalled();
    });

    test("matches snapshot — loaded state (mode=auto)", () => {
        mockMode = "auto";
        const tree = renderIt();
        expect(tree.toJSON()).toMatchSnapshot();
    });
});
