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

// @lat: [[test-push-device-targeting#Why NotificationPrefsScreen test mocks DeviceRegistrationContext]]
let mockRegistrationStatus: "idle" | "registering" | "registered" | "failed" = "registered";
let mockDeviceToken: string | null = "calling-token";
const mockRegisterPushToken = jest.fn(async () => {});
jest.mock("../../src/state/DeviceRegistrationContext", () => ({
    useDeviceRegistration: () => ({
        registrationStatus: mockRegistrationStatus,
        deviceToken: mockDeviceToken,
        registerPushToken: mockRegisterPushToken,
    }),
    useDeviceRegistrationWriter: () => () => {},
    DeviceRegistrationProvider: ({ children }: { children: React.ReactNode }) => children,
}));

const mockApiPost = jest.fn(async (..._args: unknown[]) => ({ sent: true }));
const mockApiGet = jest.fn(async (..._args: unknown[]) => ({
    // Default payload for the organization-defaults card
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

// Watch react-native's Linking.openSettings without replacing the whole react-native
// module — replacing it breaks the css-interop JSX runtime. Instead we swap out the
// live module's openSettings property and put the original back afterwards.
import { AccessibilityInfo, Linking as RNLinking } from "react-native";
const mockOpenSettings = jest.fn();
const originalOpenSettings = RNLinking.openSettings;
RNLinking.openSettings = (...args: unknown[]) => {
    mockOpenSettings(...args);
    return Promise.resolve();
};
afterAll(() => {
    RNLinking.openSettings = originalOpenSettings;
});

import React from "react";
import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react-native";
import * as Notifications from "expo-notifications";

import NotificationPrefsScreen from "../../src/screens/NotificationPrefsScreen";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { ApiRequestError, GENERIC_ERROR_MESSAGE } from "../../src/api/errors";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("NotificationPrefsScreen", () => {
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
        mockApiPost.mockReset();
        mockApiPost.mockResolvedValue({ sent: true });
        mockApiGet.mockReset();
        mockApiGet.mockResolvedValue({
            notify_on_new_position_default: true,
            notify_on_support_change_default: true,
            notify_on_summary_change_default: true,
            org_position_cadence_default: "every_change",
        });
        mockApiPatch.mockReset();
        mockApiPatch.mockResolvedValue(undefined);
        mockOpenSettings.mockReset();
        (Notifications.getPermissionsAsync as jest.Mock)
            .mockReset()
            .mockResolvedValue({ status: "granted", canAskAgain: true });
        (Notifications.requestPermissionsAsync as jest.Mock)
            .mockReset()
            .mockResolvedValue({ status: "granted", canAskAgain: true });
    });

    test("loaded state — renders heading, lead, and 4 D-37 toggles inside a Card", () => {
        wrap(<NotificationPrefsScreen />);

        expect(screen.getByText(PARITY_COPY.notifications.title)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.notifications.lead)).toBeTruthy();

        expect(screen.getByTestId("notification-prefs-card")).toBeTruthy();

        expect(screen.getByTestId("pref-toggle-botm_announcement")).toBeTruthy();
        expect(screen.getByTestId("pref-toggle-legislator_voted")).toBeTruthy();
        expect(screen.getByTestId("pref-toggle-vote_window_closing")).toBeTruthy();
        expect(screen.getByTestId("pref-toggle-org_position_taken")).toBeTruthy();

        expect(screen.getByText(PARITY_COPY.notifications.botmAnnouncement.label)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.notifications.botmAnnouncement.description)).toBeTruthy();
        expect(screen.getByText("Bill of the Month announcements")).toBeTruthy();
        expect(screen.getByText("We'll let you know when a new Bill of the Month is released.")).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.notifications.legislatorVoted.label)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.notifications.voteWindowClosing.label)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.notifications.orgPositionTaken.label)).toBeTruthy();
    });

    test("loading state — shows ActivityIndicator with accessibility label", () => {
        mockLoading = true;
        wrap(<NotificationPrefsScreen />);
        expect(screen.getByLabelText("Loading preferences")).toBeTruthy();
    });

    test("error state — renders PARITY_COPY.notifications.errorSave inline", () => {
        mockError = new Error("boom");
        wrap(<NotificationPrefsScreen />);
        const errorNode = screen.getByTestId("notification-prefs-error");
        expect(errorNode).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.notifications.errorSave)).toBeTruthy();
    });

    test("calls toggle on switch press with the verified D-37 key + next value", () => {
        wrap(<NotificationPrefsScreen />);
        // PreferenceToggle renders a static ListRow with a Switch inside; the row itself isn't
        // tappable. Only the Switch reports valueChange, so fire the event on pref-switch-{key}.
        fireEvent(screen.getByTestId("pref-switch-botm_announcement"), "valueChange", false);
        expect(mockToggle).toHaveBeenCalledWith("botm_announcement", false);
    });

    describe("Push tab", () => {
        test("loading state — shows ActivityIndicator with accessibility label", async () => {
            // Hold the permission promise open so the tab stays in "loading".
            let resolvePerm: (v: { status: string; canAskAgain: boolean }) => void = () => {};
            (Notifications.getPermissionsAsync as jest.Mock).mockImplementation(
                () =>
                    new Promise((resolve) => {
                        resolvePerm = resolve;
                    }),
            );
            wrap(<NotificationPrefsScreen />);
            expect(screen.getByLabelText("Loading push permission status")).toBeTruthy();
            // @lat: [[mobile-jest-first-pass-test-notes#Flushing push permission state updates with act]]
            await act(async () => {
                resolvePerm({ status: "granted", canAskAgain: true });
            });
            expect(screen.queryByLabelText("Loading push permission status")).toBeNull();
        });

        test("undetermined state — renders enable CTA which calls requestPermissionsAsync", async () => {
            (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
                status: "undetermined",
                canAskAgain: true,
            });
            wrap(<NotificationPrefsScreen />);
            const cta = await screen.findByTestId("push-enable-cta");
            expect(cta).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.notifications.push.enableCta)).toBeTruthy();
            // The send-test button must be hidden while push permission is not granted.
            expect(screen.queryByTestId("push-test-cta")).toBeNull();

            fireEvent.press(cta);
            await waitFor(() => expect(Notifications.requestPermissionsAsync).toHaveBeenCalled());
            await waitFor(() => expect(mockRegisterPushToken).toHaveBeenCalled());
        });

        test("denied state — shows denied copy + Go to Settings CTA which opens settings", async () => {
            (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
                status: "denied",
                canAskAgain: false,
            });
            wrap(<NotificationPrefsScreen />);
            await screen.findByTestId("push-settings-cta");

            expect(screen.getByText(PARITY_COPY.notifications.push.deniedCopy)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.notifications.push.settingsCta)).toBeTruthy();
            // The send-test button must be hidden once permission has been denied.
            expect(screen.queryByTestId("push-test-cta")).toBeNull();

            fireEvent.press(screen.getByTestId("push-settings-cta"));
            expect(mockOpenSettings).toHaveBeenCalled();
        });

        test("granted-pending-registration state — HIDES Send test CTA (HIGH item 3b)", async () => {
            (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
                status: "granted",
                canAskAgain: true,
            });
            mockRegistrationStatus = "registering";
            wrap(<NotificationPrefsScreen />);
            await screen.findByTestId("push-registering-status");

            expect(screen.getByText(PARITY_COPY.notifications.push.registeringCopy)).toBeTruthy();
            expect(screen.queryByTestId("push-test-cta")).toBeNull();
        });

        test("granted-and-registered state — shows subscribed copy + Send test CTA enabled", async () => {
            (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
                status: "granted",
                canAskAgain: true,
            });
            mockRegistrationStatus = "registered";
            mockDeviceToken = "calling-token";
            wrap(<NotificationPrefsScreen />);
            await screen.findByTestId("push-test-cta");

            expect(screen.getByText(PARITY_COPY.notifications.push.subscribedCopy)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.notifications.push.testCta)).toBeTruthy();
            expect(screen.queryByTestId("push-registering-status")).toBeNull();
        });

        test("test-send POSTs to /api/v1/notifications/test_push with calling device's push_token (HIGH 3a)", async () => {
            (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
                status: "granted",
                canAskAgain: true,
            });
            (Notifications.getDevicePushTokenAsync as jest.Mock).mockResolvedValue({ data: "calling-token" });
            mockRegistrationStatus = "registered";
            mockDeviceToken = "calling-token";
            wrap(<NotificationPrefsScreen />);
            const testCta = await screen.findByTestId("push-test-cta");

            fireEvent.press(testCta);
            await waitFor(() => expect(mockApiPost).toHaveBeenCalled());

            const [path, body] = mockApiPost.mock.calls[0];
            expect(path).toBe("/api/v1/notifications/test_push");
            expect(body).toEqual({ push_token: "calling-token" });

            await waitFor(() => expect(screen.getByText(PARITY_COPY.notifications.push.testSentCopy)).toBeTruthy());
        });

        test("test-send-error state — POST failure renders error copy", async () => {
            (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
                status: "granted",
                canAskAgain: true,
            });
            mockRegistrationStatus = "registered";
            mockDeviceToken = "calling-token";
            mockApiPost.mockRejectedValueOnce(new Error("boom"));
            wrap(<NotificationPrefsScreen />);
            const testCta = await screen.findByTestId("push-test-cta");

            fireEvent.press(testCta);
            await waitFor(() =>
                expect(screen.getByText(PARITY_COPY.notifications.push.testSendErrorCopy)).toBeTruthy(),
            );
        });

        test("H2 invariant — Push tab does NOT call getExpoPushTokenAsync", async () => {
            (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
                status: "granted",
                canAskAgain: true,
            });
            wrap(<NotificationPrefsScreen />);
            await screen.findByTestId("push-test-cta");
            expect(Notifications.getExpoPushTokenAsync).not.toHaveBeenCalled();
        });
    });

    // The card that sets account-wide defaults for organization notifications.
    describe("OrgDefaultsCard (Phase 61 D-10, REQ-5)", () => {
        // @lat: [[mobile-jest-first-pass-test-notes#Asynchronous assertions for organization defaults card]]
        test("renders org-defaults card title 'Organization position updates'", async () => {
            wrap(<NotificationPrefsScreen />);
            expect(await screen.findByText("Organization position updates")).toBeTruthy();
        });

        test("renders 3 default event-type toggles and cadence picker", async () => {
            wrap(<NotificationPrefsScreen />);
            expect(await screen.findByTestId("org-default-toggle-new-position")).toBeTruthy();
            expect(screen.getByTestId("org-default-toggle-support-change")).toBeTruthy();
            expect(screen.getByTestId("org-default-toggle-summary-change")).toBeTruthy();
            expect(screen.getByTestId("org-defaults-cadence-picker")).toBeTruthy();
        });

        test("describes every default event as Sway recording it, never the organization acting", async () => {
            wrap(<NotificationPrefsScreen />);
            expect(
                await screen.findByText(
                    "Notify by default when Sway records a change in this organization's for/against position.",
                ),
            ).toBeTruthy();
            expect(
                screen.getByText(
                    "Notify by default when Sway records a change to this organization's position summary.",
                ),
            ).toBeTruthy();
            expect(screen.queryByText(/this org (changes|updates)/)).toBeNull();
        });

        test("fetches GET /api/v1/notification_preferences/org_defaults on mount", async () => {
            wrap(<NotificationPrefsScreen />);
            await waitFor(() =>
                expect(mockApiGet).toHaveBeenCalledWith("/api/v1/notification_preferences/org_defaults"),
            );
        });

        test("Save patches /api/v1/notification_preferences/org_defaults", async () => {
            wrap(<NotificationPrefsScreen />);
            await screen.findByTestId("org-default-toggle-new-position");
            fireEvent.press(screen.getByTestId("org-defaults-save"));
            await waitFor(() => expect(mockApiPatch).toHaveBeenCalled());
            const [path] = mockApiPatch.mock.calls[0];
            expect(path).toBe("/api/v1/notification_preferences/org_defaults");
        });
    });

    // @lat: [[mobile-notification-prefs-screen#Save feedback and pinned footer]]
    describe("Save Preferences footer and feedback", () => {
        const loadedScreen = async () => {
            wrap(<NotificationPrefsScreen />);
            await screen.findByTestId("org-default-toggle-new-position");
        };

        test("the save button sits in a footer outside the scroll container", async () => {
            await loadedScreen();
            const scroll = screen.getByTestId("notification-prefs-screen");
            expect(within(scroll).queryByTestId("org-defaults-save")).toBeNull();
            const footer = screen.getByTestId("notification-prefs-footer");
            expect(within(footer).getByTestId("org-defaults-save")).toBeTruthy();
        });

        test("success shows the web confirmation copy in a polite live region and announces it", async () => {
            const announce = jest.spyOn(AccessibilityInfo, "announceForAccessibility").mockImplementation(() => {});
            await loadedScreen();
            fireEvent.press(screen.getByTestId("org-defaults-save"));
            const saved = await screen.findByTestId("notification-prefs-save-status");
            expect(saved.props.accessibilityLiveRegion).toBe("polite");
            expect(within(saved).getByText(PARITY_COPY.notifications.saved)).toBeTruthy();
            expect(announce).toHaveBeenCalledWith(PARITY_COPY.notifications.saved);
            announce.mockRestore();
        });

        test("the confirmation clears itself after a few seconds", async () => {
            jest.useFakeTimers();
            try {
                await loadedScreen();
                fireEvent.press(screen.getByTestId("org-defaults-save"));
                await screen.findByTestId("notification-prefs-save-status");
                await act(async () => {
                    jest.advanceTimersByTime(5000);
                });
                expect(screen.queryByTestId("notification-prefs-save-status")).toBeNull();
            } finally {
                jest.useRealTimers();
            }
        });

        test("editing a choice after a save clears the stale confirmation", async () => {
            await loadedScreen();
            fireEvent.press(screen.getByTestId("org-defaults-save"));
            await screen.findByTestId("notification-prefs-save-status");
            fireEvent(screen.getByTestId("pref-switch-notify_on_new_position_default"), "valueChange", false);
            expect(screen.queryByTestId("notification-prefs-save-status")).toBeNull();
        });

        test("failure shows a generic error and keeps the chosen values for a retry", async () => {
            mockApiPatch.mockRejectedValueOnce(new Error("HTTP 500"));
            await loadedScreen();
            fireEvent(screen.getByTestId("pref-switch-notify_on_new_position_default"), "valueChange", false);
            fireEvent.press(screen.getByTestId("org-defaults-save"));
            const err = await screen.findByTestId("notification-prefs-save-error");
            expect(err.props.accessibilityRole).toBe("alert");
            expect(within(err).getByText(PARITY_COPY.notifications.saveError)).toBeTruthy();
            expect(screen.queryByTestId("notification-prefs-save-status")).toBeNull();
            expect(screen.getByTestId("pref-switch-notify_on_new_position_default").props.value).toBe(false);

            fireEvent.press(screen.getByTestId("org-defaults-save"));
            await waitFor(() => expect(mockApiPatch).toHaveBeenCalledTimes(2));
            expect(mockApiPatch.mock.calls[1][1]).toMatchObject({ notify_on_new_position_default: false });
            await screen.findByTestId("notification-prefs-save-status");
            expect(screen.queryByTestId("notification-prefs-save-error")).toBeNull();
        });

        test("a client-error response shows the server's message", async () => {
            mockApiPatch.mockRejectedValueOnce(
                new ApiRequestError("invalid", "Cadence is not supported", undefined, 422),
            );
            await loadedScreen();
            fireEvent.press(screen.getByTestId("org-defaults-save"));
            const err = await screen.findByTestId("notification-prefs-save-error");
            expect(within(err).getByText("Cadence is not supported")).toBeTruthy();
        });

        test("a server-error response never leaks its raw message", async () => {
            mockApiPatch.mockRejectedValueOnce(new ApiRequestError("http_500", "HTTP 500", undefined, 500));
            await loadedScreen();
            fireEvent.press(screen.getByTestId("org-defaults-save"));
            const err = await screen.findByTestId("notification-prefs-save-error");
            expect(within(err).getByText(PARITY_COPY.notifications.saveError)).toBeTruthy();
            expect(screen.queryByText("HTTP 500")).toBeNull();
        });

        test("a client-error response carrying the generic fallback message shows the screen's own copy", async () => {
            mockApiPatch.mockRejectedValueOnce(new ApiRequestError("http_400", GENERIC_ERROR_MESSAGE, undefined, 400));
            await loadedScreen();
            fireEvent.press(screen.getByTestId("org-defaults-save"));
            const err = await screen.findByTestId("notification-prefs-save-error");
            expect(within(err).getByText(PARITY_COPY.notifications.saveError)).toBeTruthy();
            expect(screen.queryByText(GENERIC_ERROR_MESSAGE)).toBeNull();
        });

        test("a failed load of the defaults keeps Save disabled so placeholders never overwrite saved settings", async () => {
            mockApiGet.mockRejectedValueOnce(new Error("HTTP 500"));
            wrap(<NotificationPrefsScreen />);
            await screen.findByTestId("org-defaults-error");
            const save = screen.getByTestId("org-defaults-save");
            expect(save.props.accessibilityState.disabled).toBe(true);
            fireEvent.press(save);
            expect(mockApiPatch).not.toHaveBeenCalled();
        });

        test("the button is busy and disabled while the request is in flight, so a second tap sends nothing", async () => {
            let finish: () => void = () => {};
            mockApiPatch.mockImplementationOnce(
                () =>
                    new Promise<undefined>((resolve) => {
                        finish = () => resolve(undefined);
                    }),
            );
            await loadedScreen();
            const save = screen.getByTestId("org-defaults-save");
            fireEvent.press(save);
            await waitFor(() =>
                expect(screen.getByTestId("org-defaults-save").props.accessibilityState.busy).toBe(true),
            );
            expect(screen.getByTestId("org-defaults-save").props.accessibilityState.disabled).toBe(true);
            expect(
                within(screen.getByTestId("org-defaults-save")).getByText(PARITY_COPY.notifications.saving),
            ).toBeTruthy();
            fireEvent.press(screen.getByTestId("org-defaults-save"));
            expect(mockApiPatch).toHaveBeenCalledTimes(1);

            await act(async () => {
                finish();
            });
            await screen.findByTestId("notification-prefs-save-status");
            expect(screen.getByTestId("org-defaults-save").props.accessibilityState.disabled).toBe(false);
        });
    });

    describe("snapshots (Phase 37 Plan 06 evidence pack)", () => {
        test("loaded state with 4 toggles + Push tab granted-and-registered", async () => {
            (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
                status: "granted",
                canAskAgain: true,
            });
            mockRegistrationStatus = "registered";
            mockDeviceToken = "calling-token";
            const tree = wrap(<NotificationPrefsScreen />);
            await screen.findByTestId("push-test-cta");
            expect(tree.toJSON()).toMatchSnapshot();
        });

        test("granted-but-pending-registration (Plan 04 new state)", async () => {
            (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
                status: "granted",
                canAskAgain: true,
            });
            mockRegistrationStatus = "registering";
            const tree = wrap(<NotificationPrefsScreen />);
            await screen.findByTestId("push-registering-status");
            expect(tree.toJSON()).toMatchSnapshot();
        });
    });
});
