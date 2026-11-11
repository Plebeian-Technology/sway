import { reportOnce } from "app/frontend/sway_utils/report_once";

// @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
const HUMAN_DISMISS_FLOOR_MS = 750;

export type PasskeyFailureContext = {
    elapsedMs: number;
    rpId?: string;
};

// @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
export const classifyPasskeyFailure = (error: unknown, { elapsedMs }: PasskeyFailureContext): string | null => {
    if (typeof window !== "undefined" && window.isSecureContext === false) return "insecure-context";
    if (typeof window !== "undefined" && typeof window.PublicKeyCredential === "undefined") {
        return "no-webauthn-support";
    }

    if (!(error instanceof DOMException)) return "not-a-dom-exception";

    if (error.name === "AbortError") return null;

    if (error.name === "NotAllowedError") {
        return elapsedMs < HUMAN_DISMISS_FLOOR_MS ? "refused-before-any-prompt" : null;
    }

    return `dom-exception-${error.name}`;
};

// @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
export const reportPasskeyFailure = (error: unknown, context: PasskeyFailureContext): string | null => {
    const reason = classifyPasskeyFailure(error, context);
    if (!reason) return null;

    reportOnce(`passkey-discoverable-${reason}`, `Discoverable passkey sign-in failed: ${reason}`, {
        extra: {
            reason,
            elapsedMs: context.elapsedMs,
            rpId: context.rpId ?? null,
            origin: typeof window === "undefined" ? null : window.location.origin,
            isSecureContext: typeof window === "undefined" ? null : window.isSecureContext,
            errorName: error instanceof DOMException ? error.name : null,
            errorMessage: error instanceof Error ? error.message : String(error),
        },
    });

    return reason;
};
