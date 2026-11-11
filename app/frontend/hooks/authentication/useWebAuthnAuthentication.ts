import { clearIdentityCaches, IDENTITY_CHANGE_RETRY, prepareIdentityChange } from "./prepareIdentityChange";
import { router, useHttp } from "@inertiajs/react";
import {
    get,
    handleError,
    logDev,
    notify,
    PublicKeyCredentialRequestOptionsJSON,
    PublicKeyCredentialWithAssertionJSON,
} from "app/frontend/sway_utils";
import { reportPasskeyFailure } from "app/frontend/sway_utils/passkey_failure";
import { handleThrottledError } from "app/frontend/hooks/authentication/handleThrottledError";
import { useCallback, useState } from "react";

const AUTHENTICATE_ROUTE = "/users/webauthn/sessions";
const VERIFY_ROUTE = "/users/webauthn/sessions/callback";
// @lat: [[discoverable-passkey-design#useWebAuthnAuthentication.startDiscoverableAuthentication return contract]]
const DISCOVERABLE_AUTHENTICATE_ROUTE = "/users/webauthn/sessions/discoverable_challenge";
const DISCOVERABLE_VERIFY_ROUTE = "/users/webauthn/sessions/discoverable_callback";
// @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
const CHALLENGE_REQUEST_FAILED = "challenge-request-failed";

// @lat: [[decoy-challenge-non-disclosure#How the web sign-in flow (Users::Webauthn::SessionsController) achieves the same non-disclosure]]
type StartAuthenticationResponse =
    | { flow: "passkey"; options: PublicKeyCredentialRequestOptionsJSON }
    | { flow: "sms"; success: boolean };

type DiscoverableChallengeResponse = { flow: "passkey"; options: PublicKeyCredentialRequestOptionsJSON };

export const useWebAuthnAuthentication = (onThrottled?: (until: Date | null) => void) => {
    const http = useHttp<Record<string, any>>({});
    const [isLoading, setLoading] = useState<boolean>(false);
    // @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
    const [discoverableFailure, setDiscoverableFailure] = useState<string | null>(null);

    const startAuthentication = useCallback(
        async (phone: string): Promise<PublicKeyCredentialWithAssertionJSON | boolean | void> => {
            const controller = new AbortController();

            setLoading(true);
            try {
                http.transform(() => ({ phone }));
                const result = (await http.post(AUTHENTICATE_ROUTE)) as StartAuthenticationResponse;

                if (!result) return;

                if (result.flow === "sms") {
                    return result.success;
                }

                return get({ publicKey: result.options, signal: controller.signal }).catch((e) => {
                    handleError(e);
                });
            } catch (e) {
                if (handleThrottledError(e, "sign_in", onThrottled)) {
                    return;
                }
                throw e;
            } finally {
                setLoading(false);
            }
        },
        [http, onThrottled],
    );

    const verifyAuthentication = useCallback(
        async (phone: string, publicKeyCredential: PublicKeyCredentialWithAssertionJSON) => {
            if (!publicKeyCredential) {
                setLoading(false);
                return;
            }

            logDev("useWebAuthnAuthentication.verifyAuthentication - posting credential via Inertia router");

            // @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
            setLoading(true);
            try {
                await prepareIdentityChange();
            } catch {
                setLoading(false);
                notify({ level: "error", title: IDENTITY_CHANGE_RETRY });
                return;
            }

            router.post(VERIFY_ROUTE, { phone, publicKeyCredential } as any, {
                preserveState: false,
                onBeforeUpdate: clearIdentityCaches,
                onFinish: () => setLoading(false),
            });
        },
        [],
    );

    // @lat: [[discoverable-passkey-design#useWebAuthnAuthentication.startDiscoverableAuthentication return contract]]
    const startDiscoverableAuthentication = useCallback(async (): Promise<
        PublicKeyCredentialWithAssertionJSON | undefined
    > => {
        setLoading(true);
        setDiscoverableFailure(null);
        try {
            const result = (await http.post(DISCOVERABLE_AUTHENTICATE_ROUTE)) as DiscoverableChallengeResponse;
            if (!result) {
                setDiscoverableFailure(CHALLENGE_REQUEST_FAILED);
                return undefined;
            }

            const startedAt = Date.now();
            try {
                return await get({ publicKey: result.options });
            } catch (e) {
                // @lat: [[discoverable-passkey-design#useWebAuthnAuthentication.startDiscoverableAuthentication return contract]]
                const reason = reportPasskeyFailure(e, {
                    elapsedMs: Date.now() - startedAt,
                    rpId: result.options.rpId,
                });
                // @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
                setDiscoverableFailure(reason);
                // @lat: [[discoverable-passkey-design#useWebAuthnAuthentication.startDiscoverableAuthentication return contract]]
                logDev("useWebAuthnAuthentication.startDiscoverableAuthentication - no passkey used", e);
                return undefined;
            }
        } catch (e) {
            logDev("useWebAuthnAuthentication.startDiscoverableAuthentication - challenge request failed", e);
            // @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
            setDiscoverableFailure(CHALLENGE_REQUEST_FAILED);
            return undefined;
        } finally {
            setLoading(false);
        }
    }, [http]);

    const verifyDiscoverableAuthentication = useCallback(
        async (publicKeyCredential: PublicKeyCredentialWithAssertionJSON) => {
            if (!publicKeyCredential) {
                setLoading(false);
                return;
            }

            setLoading(true);
            try {
                await prepareIdentityChange();
            } catch {
                setLoading(false);
                notify({ level: "error", title: IDENTITY_CHANGE_RETRY });
                return;
            }

            router.post(DISCOVERABLE_VERIFY_ROUTE, { publicKeyCredential } as any, {
                preserveState: false,
                onBeforeUpdate: clearIdentityCaches,
                onFinish: () => setLoading(false),
            });
        },
        [],
    );

    return {
        startAuthentication,
        verifyAuthentication,
        startDiscoverableAuthentication,
        verifyDiscoverableAuthentication,
        discoverableFailure,
        isLoading,
    } as const;
};
