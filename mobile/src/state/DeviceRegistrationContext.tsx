// @lat: [[mobile-push-registration-gating#Why the gate is server confirmation, not OS permission]]
import React, { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from "react";

export type RegistrationStatus = "idle" | "registering" | "registered" | "failed";

export interface DeviceRegistrationState {
    registrationStatus: RegistrationStatus;
    deviceToken: string | null;
    registerPushToken?: () => Promise<void>;
}

export interface DeviceRegistrationContextValue extends DeviceRegistrationState {
    setRegistration: (next: Partial<DeviceRegistrationState>) => void;
    registerPushToken: () => Promise<void>;
}

const DEFAULT_STATE: DeviceRegistrationState = {
    registrationStatus: "idle",
    deviceToken: null,
};

const NOOP_ASYNC = async (): Promise<void> => {};

const DeviceRegistrationContext = createContext<DeviceRegistrationContextValue | null>(null);

export function DeviceRegistrationProvider({ children }: { children: ReactNode }) {
    const [state, setState] = useState<DeviceRegistrationState>(DEFAULT_STATE);
    const registerHandlerRef = useRef<(() => Promise<void>) | undefined>(undefined);

    const setRegistration = useCallback((next: Partial<DeviceRegistrationState>) => {
        if ("registerPushToken" in next) {
            registerHandlerRef.current = next.registerPushToken;
        }
        setState((prev) => ({
            registrationStatus: next.registrationStatus ?? prev.registrationStatus,
            deviceToken: next.deviceToken !== undefined ? next.deviceToken : prev.deviceToken,
        }));
    }, []);

    const registerPushToken = useCallback(async () => {
        if (registerHandlerRef.current) {
            await registerHandlerRef.current();
        }
    }, []);

    const value = useMemo<DeviceRegistrationContextValue>(
        () => ({
            ...state,
            setRegistration,
            registerPushToken,
        }),
        [state, setRegistration, registerPushToken],
    );

    return <DeviceRegistrationContext.Provider value={value}>{children}</DeviceRegistrationContext.Provider>;
}

export function useDeviceRegistration(): DeviceRegistrationState & { registerPushToken: () => Promise<void> } {
    const ctx = useContext(DeviceRegistrationContext);
    if (!ctx) return { ...DEFAULT_STATE, registerPushToken: NOOP_ASYNC };
    return {
        registrationStatus: ctx.registrationStatus,
        deviceToken: ctx.deviceToken,
        registerPushToken: ctx.registerPushToken,
    };
}

export function useDeviceRegistrationWriter(): DeviceRegistrationContextValue["setRegistration"] {
    const ctx = useContext(DeviceRegistrationContext);
    if (!ctx) return () => {};
    return ctx.setRegistration;
}
