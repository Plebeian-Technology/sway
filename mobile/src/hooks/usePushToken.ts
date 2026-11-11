// @lat: [[device-push-token-management#usePushToken, the mobile client hook]]
import { useCallback, useEffect } from "react";
import { Platform } from "react-native";
import * as Notifications from "expo-notifications";
import Constants from "expo-constants";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { useSession } from "./useSession";
import { useDeviceRegistrationWriter } from "../state/DeviceRegistrationContext";

export function usePushToken(): void {
    const { isAuthenticated } = useSession();
    // @lat: [[device-push-token-management#usePushToken, the mobile client hook]]
    const setRegistration = useDeviceRegistrationWriter();

    const performRegistration = useCallback(
        async (isCancelled?: () => boolean): Promise<void> => {
            try {
                // @lat: [[device-push-token-management#usePushToken, the mobile client hook]]
                const current = await Notifications.getPermissionsAsync();
                let status: string = current.status;
                if (status !== "granted" && current.canAskAgain) {
                    status = (await Notifications.requestPermissionsAsync()).status;
                }
                if (status !== "granted") return;
                if (isCancelled?.()) return;

                const deviceToken = await Notifications.getDevicePushTokenAsync();
                if (isCancelled?.()) return;

                setRegistration({ deviceToken: deviceToken.data, registrationStatus: "registering" });
                await apiClient.patch(Routes.devicePushToken(), {
                    push_token: deviceToken.data,
                    platform: Platform.OS,
                    app_version: Constants.expoConfig?.version,
                });
                if (isCancelled?.()) return;
                setRegistration({ registrationStatus: "registered" });
            } catch {
                if (isCancelled?.()) return;
                setRegistration({ registrationStatus: "failed" });
            }
        },
        [setRegistration],
    );

    useEffect(() => {
        if (!isAuthenticated) {
            setRegistration({ registrationStatus: "idle", deviceToken: null, registerPushToken: undefined });
            return;
        }

        let cancelled = false;
        const isCancelled = () => cancelled;

        setRegistration({ registerPushToken: () => performRegistration(isCancelled) });
        void performRegistration(isCancelled);

        const sub = Notifications.addPushTokenListener(async (newT) => {
            if (cancelled) return;
            setRegistration({ deviceToken: newT.data, registrationStatus: "registering" });
            try {
                await apiClient.patch(Routes.devicePushToken(), {
                    push_token: newT.data,
                    platform: Platform.OS,
                });
                if (cancelled) return;
                setRegistration({ registrationStatus: "registered" });
            } catch {
                if (cancelled) return;
                setRegistration({ registrationStatus: "failed" });
            }
        });

        return () => {
            cancelled = true;
            sub.remove();
        };
        // oxlint-disable-next-line react-hooks/exhaustive-deps
    }, [isAuthenticated]);
}
