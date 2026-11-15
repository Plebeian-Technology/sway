// @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey error translation]]
import { Platform } from "react-native";
import * as Sentry from "@sentry/react-native";
import { Passkey, PasskeyCreateRequest, PasskeyGetRequest } from "react-native-passkey";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { ApiRequestError } from "../api/errors";
import { tokenStore } from "./tokenStore";
import { sessionStore, SessionEnvelope } from "./sessionStore";
import { authEvents } from "./authEvents";

export class PasskeyUnsupportedError extends Error {
    constructor(message = "passkey_unsupported") {
        super(message);
        this.name = "PasskeyUnsupportedError";
    }
}

export class PasskeyProviderMissingError extends Error {
    constructor(message = "passkey_provider_missing") {
        super(message);
        this.name = "PasskeyProviderMissingError";
    }
}

export class PasskeyCreateUnsupportedError extends Error {
    constructor(message = "passkey_create_unsupported") {
        super(message);
        this.name = "PasskeyCreateUnsupportedError";
    }
}

export class NoPasskeyError extends Error {
    constructor(message = "no_credential") {
        super(message);
        this.name = "NoPasskeyError";
    }
}

export class SessionSaveError extends Error {
    constructor(
        message = "Your account is ready, but this device could not save your sign-in. Sign in with your passkey.",
    ) {
        super(message);
        this.name = "SessionSaveError";
    }
}

interface AuthCallbackResponse {
    bearer_token: string;
    device_id: number;
    user: { id: number; [key: string]: unknown };
    expires_at: string;
}

// @lat: [[passkey-only-sms-bootstrap#Api::V1::RegistrationsController: the two-step enrollment shape and token handling]]
type ChallengeOptions = PasskeyGetRequest & { challenge_id: string };
type RegistrationOptions = PasskeyCreateRequest & { challenge_id: string };

// @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
type ChallengeResponse = { flow: "sms" } | { flow: "passkey"; challenge_id: string; options: PasskeyGetRequest };

// @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey error translation#A session the device cannot save]]
async function persistSession(resp: AuthCallbackResponse): Promise<void> {
    try {
        await tokenStore.set(resp.bearer_token);
        const envelope: SessionEnvelope = {
            bearer_token: resp.bearer_token,
            device_id: resp.device_id,
            user_id: resp.user.id,
            expires_at: resp.expires_at,
        };
        await sessionStore.set(envelope);
        authEvents.emit("signed_in");
    } catch {
        await Promise.allSettled([tokenStore.clear(), sessionStore.clear()]);
        throw new SessionSaveError();
    }
}

// @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey error translation]]
function mapPasskeyError(e: unknown, registering = false): Error {
    const errObj = e as { error?: unknown; message?: unknown };
    const name = String(errObj?.error ?? "");
    const detail = String(errObj?.message ?? "");
    // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey error translation]]
    if (__DEV__) {
        // oxlint-disable-next-line no-console
        console.warn("[passkeyAuth] native error", { name, detail, raw: e });
    }
    if (name === "NotSupported")
        return registering ? new PasskeyCreateUnsupportedError() : new PasskeyUnsupportedError();
    if (name === "NoCreateOption") return new PasskeyProviderMissingError();
    if (name === "BadConfiguration" && Platform.OS === "android" && registering)
        return new PasskeyProviderMissingError();
    if (name === "UserCancelled" || name === "NoCredentials") return new NoPasskeyError();
    Sentry.captureMessage("passkey_native_error", { level: "warning", tags: { passkey_error: name || "unknown" } });
    return e instanceof Error ? e : new Error(detail || name || "passkey_failed");
}

async function completeCeremony(
    callbackRoute: string,
    payloadKey: "session" | "registration",
    challengeId: string,
    credential: unknown,
): Promise<{ user: AuthCallbackResponse["user"] }> {
    const resp = await apiClient.post<AuthCallbackResponse>(callbackRoute, {
        [payloadKey]: {
            challenge_id: challengeId,
            credential,
            platform: Platform.OS,
        },
    });

    await persistSession(resp);
    return { user: resp.user };
}

export const passkeyAuth = {
    isSupported(): boolean {
        return Passkey.isSupported();
    },

    async signIn(phone: string): Promise<{ user: AuthCallbackResponse["user"] }> {
        if (!Passkey.isSupported()) {
            throw new PasskeyUnsupportedError();
        }

        let challenge: ChallengeResponse;
        try {
            challenge = await apiClient.post<ChallengeResponse>(Routes.sessionsChallenge(), {
                session: { phone },
            });
        } catch (e) {
            // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
            if (e instanceof ApiRequestError && e.code === "no_passkey_enrolled") {
                throw new NoPasskeyError();
            }
            throw e;
        }

        // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
        if (challenge.flow !== "passkey") {
            throw new NoPasskeyError();
        }

        let credential;
        try {
            credential = await Passkey.get(challenge.options);
        } catch (e) {
            throw mapPasskeyError(e);
        }

        return completeCeremony(Routes.sessionsCallback(), "session", challenge.challenge_id, credential);
    },

    // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey ceremonies]]
    async signInDiscoverable(): Promise<{ user: AuthCallbackResponse["user"] }> {
        if (!Passkey.isSupported()) {
            throw new PasskeyUnsupportedError();
        }

        const options = await apiClient.post<ChallengeOptions>(Routes.sessionsDiscoverableChallenge(), {});

        let credential;
        try {
            credential = await Passkey.get(options);
        } catch (e) {
            throw mapPasskeyError(e);
        }

        return completeCeremony(Routes.sessionsCallback(), "session", options.challenge_id, credential);
    },

    // @lat: [[passkey-only-sms-bootstrap#mobile/src/auth/smsAuth.ts: proving you hold a phone number, before your first passkey]]
    async register(phone: string, smsVerifiedToken: string): Promise<{ user: AuthCallbackResponse["user"] }> {
        const options = await apiClient.post<RegistrationOptions>(Routes.registrations(), {
            registration: { sms_verified_token: smsVerifiedToken, phone },
        });

        let credential;
        try {
            credential = await Passkey.create(options);
        } catch (e) {
            throw mapPasskeyError(e, true);
        }

        return completeCeremony(Routes.registrationsCallback(), "registration", options.challenge_id, credential);
    },

    // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey ceremonies]]
    async addPasskey(smsVerifiedToken: string, label: string): Promise<{ id: number; label: string }> {
        const options = await apiClient.post<RegistrationOptions>(Routes.addPasskey(), {
            passkey: { sms_verified_token: smsVerifiedToken, label },
        });

        let credential;
        try {
            credential = await Passkey.create(options);
        } catch (e) {
            throw mapPasskeyError(e);
        }

        return apiClient.post<{ id: number; label: string }>(Routes.addPasskeyCallback(), {
            passkey: { challenge_id: options.challenge_id, credential, label },
        });
    },
};
