const mockPatch = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: {
        patch: (...args: unknown[]) => mockPatch(...(args as [string, unknown])),
    },
}));

const mockUseSession = jest.fn();
jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => mockUseSession(),
}));

import React from "react";
import { renderHook, waitFor, act } from "@testing-library/react-native";
import * as Notifications from "expo-notifications";

import { usePushToken } from "../../src/hooks/usePushToken";
import { DeviceRegistrationProvider, useDeviceRegistration } from "../../src/state/DeviceRegistrationContext";

describe("usePushToken", () => {
    beforeEach(() => {
        mockPatch.mockReset().mockResolvedValue(undefined);
        (Notifications.requestPermissionsAsync as jest.Mock).mockReset().mockResolvedValue({ status: "granted" });
        (Notifications.addPushTokenListener as jest.Mock).mockReset().mockReturnValue({ remove: jest.fn() });
        // The hook must call getDevicePushTokenAsync, never getExpoPushTokenAsync.
        // Give the device-token call a default fake answer so the checks below
        // can prove which one actually ran.
        (Notifications as unknown as { getDevicePushTokenAsync: jest.Mock }).getDevicePushTokenAsync = jest
            .fn()
            .mockResolvedValue({ data: "native-fcm-or-apns-token" });
    });

    test("does nothing when not authenticated", async () => {
        mockUseSession.mockReturnValue({ isAuthenticated: false });
        renderHook(() => usePushToken());
        await new Promise((r) => setTimeout(r, 0));
        expect(Notifications.requestPermissionsAsync).not.toHaveBeenCalled();
        expect(mockPatch).not.toHaveBeenCalled();
    });

    test("requests permission and PATCHes the native device token when authenticated", async () => {
        mockUseSession.mockReturnValue({ isAuthenticated: true });
        renderHook(() => usePushToken());
        await waitFor(() => expect(mockPatch).toHaveBeenCalled());

        expect(Notifications.requestPermissionsAsync).toHaveBeenCalled();
        // The device's own token, not the Expo one.
        expect(
            (Notifications as unknown as { getDevicePushTokenAsync: jest.Mock }).getDevicePushTokenAsync,
        ).toHaveBeenCalled();
        expect(Notifications.getExpoPushTokenAsync).not.toHaveBeenCalled();

        const [path, body] = mockPatch.mock.calls[0];
        expect(path).toBe("/api/v1/devices/push_token");
        expect(body).toEqual(
            expect.objectContaining({
                push_token: "native-fcm-or-apns-token",
                platform: expect.stringMatching(/^(ios|android)$/),
            }),
        );
    });

    test("does NOT PATCH when permission is denied", async () => {
        mockUseSession.mockReturnValue({ isAuthenticated: true });
        (Notifications.requestPermissionsAsync as jest.Mock).mockResolvedValueOnce({ status: "denied" });
        renderHook(() => usePushToken());
        await new Promise((r) => setTimeout(r, 50));
        expect(mockPatch).not.toHaveBeenCalled();
    });

    test("subscribes to addPushTokenListener for token rotation", async () => {
        mockUseSession.mockReturnValue({ isAuthenticated: true });
        renderHook(() => usePushToken());
        await waitFor(() => expect(Notifications.addPushTokenListener).toHaveBeenCalled());
    });

    test("catches getPermissionsAsync rejection and marks registrationStatus failed", async () => {
        mockUseSession.mockReturnValue({ isAuthenticated: true });
        (Notifications.getPermissionsAsync as jest.Mock).mockRejectedValueOnce(new Error("bridge error"));
        const wrapper = ({ children }: { children: React.ReactNode }) =>
            React.createElement(DeviceRegistrationProvider, null, children);
        const { result } = renderHook(
            () => {
                usePushToken();
                return useDeviceRegistration();
            },
            { wrapper },
        );
        await waitFor(() => expect(result.current.registrationStatus).toBe("failed"));
    });

    test("resets registration state to idle when unauthenticated and exposes registerPushToken()", async () => {
        let authed = true;
        mockUseSession.mockImplementation(() => ({ isAuthenticated: authed }));
        (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
            status: "granted",
            canAskAgain: true,
        });
        const wrapper = ({ children }: { children: React.ReactNode }) =>
            React.createElement(DeviceRegistrationProvider, null, children);
        const { result, rerender } = renderHook(
            () => {
                usePushToken();
                return useDeviceRegistration();
            },
            { wrapper },
        );
        await waitFor(() => expect(result.current.registrationStatus).toBe("registered"));

        mockPatch.mockClear();
        await act(async () => {
            await result.current.registerPushToken();
        });
        expect(mockPatch).toHaveBeenCalledWith("/api/v1/devices/push_token", expect.any(Object));

        authed = false;
        rerender({});
        await waitFor(() => expect(result.current.registrationStatus).toBe("idle"));
        expect(result.current.deviceToken).toBeNull();
    });

    test("ignores in-flight addPushTokenListener completion after sign-out cleanup", async () => {
        let authed = true;
        mockUseSession.mockImplementation(() => ({ isAuthenticated: authed }));
        (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
            status: "granted",
            canAskAgain: true,
        });
        let capturedListener: ((token: { data: string }) => Promise<void>) | null = null;
        (Notifications.addPushTokenListener as jest.Mock).mockImplementation((cb) => {
            capturedListener = cb;
            return { remove: jest.fn() };
        });

        const wrapper = ({ children }: { children: React.ReactNode }) =>
            React.createElement(DeviceRegistrationProvider, null, children);
        const { result, rerender } = renderHook(
            () => {
                usePushToken();
                return useDeviceRegistration();
            },
            { wrapper },
        );
        await waitFor(() => expect(result.current.registrationStatus).toBe("registered"));

        let resolveRotationPatch: (() => void) | null = null;
        mockPatch.mockImplementationOnce(
            () =>
                new Promise<void>((resolve) => {
                    resolveRotationPatch = resolve;
                }),
        );

        let rotationPromise: Promise<void> | undefined;
        act(() => {
            rotationPromise = capturedListener?.({ data: "rotated-token" });
        });
        expect(result.current.registrationStatus).toBe("registering");

        authed = false;
        rerender({});
        await waitFor(() => expect(result.current.registrationStatus).toBe("idle"));

        await act(async () => {
            resolveRotationPatch?.();
            await rotationPromise;
        });

        expect(result.current.registrationStatus).toBe("idle");
        expect(result.current.deviceToken).toBeNull();
    });
});
