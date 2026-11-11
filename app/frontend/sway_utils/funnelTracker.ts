// @lat: [[registration-funnel-telemetry#Client-side telemetry dispatch and step mapping]]
import { SWAY_STORAGE } from "app/frontend/sway_utils/storage";

export interface FunnelEventPayload {
    visitor_token: string;
    step: string;
    attribution_key?: string | null;
    metadata?: Record<string, unknown>;
    timestamp: number;
    authenticity_token?: string;
}

const RECORDED_STEPS_SESSION_PREFIX = "@sway/funnel/recorded_step/";

export function getOrCreateVisitorToken(): string {
    if (typeof window === "undefined") {
        return "server-side-token";
    }

    try {
        let token = window.localStorage.getItem(SWAY_STORAGE.Local.Funnel.VisitorToken);
        if (!token) {
            token =
                typeof crypto !== "undefined" && typeof crypto.randomUUID === "function"
                    ? crypto.randomUUID()
                    : `v1-${Date.now()}-${Math.random().toString(36).substring(2, 11)}`;
            window.localStorage.setItem(SWAY_STORAGE.Local.Funnel.VisitorToken, token);
        }

        if (typeof document !== "undefined" && !document.cookie.includes("sway_visitor_token=")) {
            document.cookie = `sway_visitor_token=${encodeURIComponent(token)}; path=/; max-age=31536000; SameSite=Lax`;
        }
        return token;
    } catch {
        return "anonymous-session";
    }
}

export function captureReferralAttribution(): string | null {
    if (typeof window === "undefined") {
        return null;
    }

    try {
        const urlParams = new URLSearchParams(window.location.search);
        let attributionKey =
            urlParams.get("ref") ||
            urlParams.get("attribution") ||
            urlParams.get("s") ||
            urlParams.get("source") ||
            urlParams.get("invite_code");

        if (!attributionKey && window.location.pathname.startsWith("/s/")) {
            const shortCode = window.location.pathname.replace(/^\/s\//, "").split("/")[0];
            if (shortCode) {
                attributionKey = `s:${shortCode}`;
            }
        }

        if (!attributionKey && typeof document !== "undefined") {
            const match = document.cookie.match(/(?:^|;\s*)sway_attribution_key=([^;]+)/);
            if (match?.[1]) {
                attributionKey = decodeURIComponent(match[1]);
            }
        }

        if (attributionKey) {
            window.localStorage.setItem(SWAY_STORAGE.Local.Funnel.AttributionKey, attributionKey);
            if (typeof document !== "undefined") {
                document.cookie = `sway_attribution_key=${encodeURIComponent(attributionKey)}; path=/; max-age=2592000; SameSite=Lax`;
            }
            return attributionKey;
        }

        return window.localStorage.getItem(SWAY_STORAGE.Local.Funnel.AttributionKey) || null;
    } catch {
        return null;
    }
}

export function getAttributionKey(): string | null {
    if (typeof window === "undefined") {
        return null;
    }

    try {
        let key = window.localStorage.getItem(SWAY_STORAGE.Local.Funnel.AttributionKey);
        if (!key && typeof document !== "undefined") {
            const match = document.cookie.match(/(?:^|;\s*)sway_attribution_key=([^;]+)/);
            if (match?.[1]) {
                key = decodeURIComponent(match[1]);
            }
        }
        return key || null;
    } catch {
        return null;
    }
}

export function hasStepBeenRecordedInSession(step: string): boolean {
    if (typeof window === "undefined") return false;
    try {
        return window.sessionStorage.getItem(`${RECORDED_STEPS_SESSION_PREFIX}${step}`) === "true";
    } catch {
        return false;
    }
}

export function markStepRecordedInSession(step: string): void {
    if (typeof window === "undefined") return;
    try {
        window.sessionStorage.setItem(`${RECORDED_STEPS_SESSION_PREFIX}${step}`, "true");
    } catch {}
}

export function trackFunnelStep(
    step: string,
    metadata: Record<string, unknown> = {},
    options: { oncePerSession?: boolean } = {},
): void {
    if (typeof window === "undefined") return;

    if (options.oncePerSession && hasStepBeenRecordedInSession(step)) {
        return;
    }

    const csrfToken =
        typeof document !== "undefined"
            ? document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || undefined
            : undefined;

    const payload: FunnelEventPayload = {
        visitor_token: getOrCreateVisitorToken(),
        step,
        attribution_key: getAttributionKey(),
        metadata: {
            ...metadata,
            url: window.location.pathname,
            screen_width: window.innerWidth,
        },
        timestamp: Date.now(),
        ...(csrfToken ? { authenticity_token: csrfToken } : {}),
    };

    if (options.oncePerSession) {
        markStepRecordedInSession(step);
    }

    const endpoint = "/api/v1/funnel_events";

    let dispatched = false;
    if (typeof navigator !== "undefined" && typeof navigator.sendBeacon === "function") {
        try {
            const blob = new Blob([JSON.stringify(payload)], { type: "application/json" });
            dispatched = navigator.sendBeacon(endpoint, blob);
        } catch {
            dispatched = false;
        }
    }

    if (!dispatched && typeof fetch === "function") {
        fetch(endpoint, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
            },
            body: JSON.stringify(payload),
            keepalive: true,
        }).catch(() => {});
    }
}

export function trackFunnelStepOnce(step: string, metadata: Record<string, unknown> = {}): void {
    trackFunnelStep(step, metadata, { oncePerSession: true });
}
