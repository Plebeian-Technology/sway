// @lat: [[mobile-jest-first-pass-test-notes#Notification preferences hook mock shape]]

let mockPrefs: { key: string; enabled: boolean }[] = [];
let mockLoading = false;
let mockError: Error | null = null;
const mockToggle = jest.fn(async () => {});
const mockRefresh = jest.fn(async () => {});

jest.mock("../../src/hooks/useNotificationPrefs", () => {
    const actual = jest.requireActual("../../src/hooks/useNotificationPrefs");
    return {
        ...actual,
        useNotificationPrefs: () => ({
            prefs: mockPrefs,
            loading: mockLoading,
            error: mockError,
            toggle: mockToggle,
            refresh: mockRefresh,
        }),
    };
});

let mockRegistrationStatus: "idle" | "registering" | "registered" | "failed" = "registered";
let mockDeviceToken: string | null = "calling-token";
jest.mock("../../src/state/DeviceRegistrationContext", () => ({
    useDeviceRegistration: () => ({
        registrationStatus: mockRegistrationStatus,
        deviceToken: mockDeviceToken,
    }),
    useDeviceRegistrationWriter: () => () => {},
    DeviceRegistrationProvider: ({ children }: { children: React.ReactNode }) => children,
}));

const mockApiPost = jest.fn(async (..._args: unknown[]) => ({ sent: true }));
const mockApiGet = jest.fn(async (..._args: unknown[]) => ({
    notify_on_new_position_default: true,
    notify_on_support_change_default: true,
    notify_on_summary_change_default: true,
    org_position_cadence_default: "every_change",
}));
const mockApiPatch = jest.fn(async (..._args: unknown[]) => undefined);
jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockApiGet(...(args as [string])),
        post: (...args: unknown[]) => mockApiPost(...(args as [string, unknown])),
        patch: (...args: unknown[]) => mockApiPatch(...(args as [string, unknown])),
    },
}));

import React from "react";
import { act, fireEvent, render, screen } from "@testing-library/react-native";
import * as Notifications from "expo-notifications";

import NotificationPrefsScreen from "../../src/screens/NotificationPrefsScreen";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { ThemeProvider } from "../../src/theme/ThemeProvider";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("NotificationPrefsScreen - Empirical Adversarial Challenge", () => {
    beforeEach(() => {
        mockToggle.mockReset();
        mockToggle.mockResolvedValue(undefined);
        mockRefresh.mockReset();
        mockRefresh.mockResolvedValue(undefined);
        mockLoading = false;
        mockError = null;
        mockPrefs = [
            { key: "botm_announcement", enabled: true },
            { key: "legislator_voted", enabled: false },
            { key: "vote_window_closing", enabled: false },
            { key: "org_position_taken", enabled: false },
        ];
        mockRegistrationStatus = "registered";
        mockDeviceToken = "calling-token";
        (Notifications.getPermissionsAsync as jest.Mock)
            .mockReset()
            .mockResolvedValue({ status: "granted", canAskAgain: true });
    });

    test("1. Verifies exact testIDs for all toggle rows and switches", () => {
        wrap(<NotificationPrefsScreen />);

        expect(screen.getByTestId("notification-prefs-screen")).toBeTruthy();
        expect(screen.getByTestId("notification-prefs-card")).toBeTruthy();

        expect(screen.getByTestId("pref-toggle-botm_announcement")).toBeTruthy();
        expect(screen.getByTestId("pref-switch-botm_announcement")).toBeTruthy();

        expect(screen.getByTestId("pref-toggle-legislator_voted")).toBeTruthy();
        expect(screen.getByTestId("pref-switch-legislator_voted")).toBeTruthy();

        expect(screen.getByTestId("pref-toggle-vote_window_closing")).toBeTruthy();
        expect(screen.getByTestId("pref-switch-vote_window_closing")).toBeTruthy();

        expect(screen.getByTestId("pref-toggle-org_position_taken")).toBeTruthy();
        expect(screen.getByTestId("pref-switch-org_position_taken")).toBeTruthy();
    });

    test("2. Verifies labels and descriptions adhere to PARITY_COPY monthly terminology", () => {
        wrap(<NotificationPrefsScreen />);

        expect(screen.getByText(PARITY_COPY.notifications.title)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.notifications.lead)).toBeTruthy();
        expect(PARITY_COPY.notifications.lead).toContain("Bill of the Month is on by default");

        expect(screen.getByText(PARITY_COPY.notifications.botmAnnouncement.label)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.notifications.botmAnnouncement.description)).toBeTruthy();
        expect(PARITY_COPY.notifications.botmAnnouncement.label).toBe("Bill of the Month announcements");
        expect(PARITY_COPY.notifications.botmAnnouncement.description).toBe(
            "We'll let you know when a new Bill of the Month is released.",
        );
    });

    test("3. Toggling BotM switch fires toggle with botm_announcement and false", async () => {
        wrap(<NotificationPrefsScreen />);

        const switchComponent = screen.getByTestId("pref-switch-botm_announcement");
        expect(switchComponent.props.value).toBe(true);

        await act(async () => {
            fireEvent(switchComponent, "valueChange", false);
        });
        expect(mockToggle).toHaveBeenCalledTimes(1);
        expect(mockToggle).toHaveBeenCalledWith("botm_announcement", false);
    });

    test("4. Error state when toggle fails displays inline error message", async () => {
        mockToggle.mockRejectedValueOnce(new Error("Network failed to persist preference"));
        wrap(<NotificationPrefsScreen />);

        const switchComponent = screen.getByTestId("pref-switch-botm_announcement");
        await act(async () => {
            fireEvent(switchComponent, "valueChange", false);
        });

        expect(await screen.findByTestId("notification-prefs-error")).toBeTruthy();
        expect(screen.getByText("Network failed to persist preference")).toBeTruthy();
    });
});
