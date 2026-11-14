// @lat: [[lazy-inertia-props#Mobile JSON omission is an explicit request]]
// @lat: [[identity-and-access#Identity and access#Sessions, cookies and bearer tokens]]
import { API_BASE_URL } from "../constants/api";
import { tokenStore } from "../auth/tokenStore";
import { sessionStore } from "../auth/sessionStore";
import { ApiRequestError, UnauthorizedError, RateLimitedError, NetworkError, GENERIC_ERROR_MESSAGE } from "./errors";
import { authEvents } from "../auth/authEvents";
import { localeOverride } from "../state/localeOverride";
import { logDev } from "../utils/logging";

if (__DEV__) {
    // @lat: [[console-channels#Why the mobile app repeats the helper]]
    logDev(`[api.client] API_BASE_URL=${API_BASE_URL}`);
}

type Method = "GET" | "POST" | "PATCH" | "DELETE";

export interface RequestOptions {
    method?: Method;
    body?: unknown;
    headers?: Record<string, string>;
    timeoutMs?: number;
    signal?: AbortSignal;
}

const DEFAULT_TIMEOUT_MS = 15_000;

function safeJson(s: string): unknown {
    try {
        return JSON.parse(s);
    } catch {
        return undefined;
    }
}

// @lat: [[mobile-locale-override-design#Mobile locale override design]]
function withLocaleOverride(url: string): string {
    const id = localeOverride.get();
    if (id == null) return url;
    if (/[?&]sway_locale_id=/.test(url)) return url;
    const sep = url.includes("?") ? "&" : "?";
    return `${url}${sep}sway_locale_id=${id}`;
}

interface D29Error {
    code: string;
    message: string;
    details?: Record<string, string[]>;
}

function envelopeFrom(parsed: unknown, fallbackStatus: number): D29Error {
    if (parsed && typeof parsed === "object") {
        // @lat: [[bill-detail-error-recovery#When a bill will not load on the phone]]
        const errors = (
            parsed as {
                errors?: {
                    code?: string;
                    title?: string;
                    detail?: string;
                    source?: unknown;
                }[];
            }
        ).errors;
        if (Array.isArray(errors) && errors.length > 0) {
            const first = errors[0] ?? {};
            return {
                code: first.code ?? `http_${fallbackStatus}`,
                message: first.title ?? first.detail ?? GENERIC_ERROR_MESSAGE,
                // @lat: [[mobile-api-client-contract#Why both server error envelope shapes are converted the same way]]
                details: first.detail ? { detail: [first.detail] } : undefined,
            };
        }
        if ("error" in parsed) {
            const err = (parsed as { error?: Partial<D29Error> }).error;
            if (err && typeof err === "object") {
                return {
                    code: err.code ?? `http_${fallbackStatus}`,
                    message: err.message ?? GENERIC_ERROR_MESSAGE,
                    details: err.details,
                };
            }
        }
    }
    return { code: `http_${fallbackStatus}`, message: GENERIC_ERROR_MESSAGE };
}

async function request<T>(path: string, opts: RequestOptions = {}): Promise<T> {
    const url = withLocaleOverride(path.startsWith("http") ? path : `${API_BASE_URL}${path}`);
    const token = await tokenStore.get();

    const headers: Record<string, string> = {
        Accept: "application/json",
        ...opts.headers,
    };
    if (opts.body != null) headers["Content-Type"] = "application/json";
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const ctrl = new AbortController();
    const timeoutId = setTimeout(() => ctrl.abort(), opts.timeoutMs ?? DEFAULT_TIMEOUT_MS);
    const callerSignal = opts.signal;
    const onCallerAbort = () => ctrl.abort();
    if (callerSignal) {
        if (callerSignal.aborted) ctrl.abort();
        else callerSignal.addEventListener("abort", onCallerAbort, { once: true });
    }

    let res: Response;
    try {
        res = await fetch(url, {
            method: opts.method ?? "GET",
            headers,
            body: opts.body != null ? JSON.stringify(opts.body) : undefined,
            signal: ctrl.signal,
        });
    } catch (e: unknown) {
        // @lat: [[mobile-api-client-contract#Methods]]
        if (callerSignal?.aborted) {
            throw new ApiRequestError("aborted", "request aborted by caller");
        }
        const msg = e instanceof Error ? e.message : "Network error";
        throw new NetworkError("network_error", msg);
    } finally {
        clearTimeout(timeoutId);
        if (callerSignal) callerSignal.removeEventListener("abort", onCallerAbort);
    }

    if (res.status === 204) {
        return undefined as unknown as T;
    }

    const text = await res.text();
    const parsed = text ? safeJson(text) : undefined;

    if (res.ok) {
        return parsed as T;
    }

    const envelope = envelopeFrom(parsed, res.status);

    if (res.status === 401) {
        if (token !== null && (await tokenStore.get()) === token) {
            await tokenStore.clear();
            await sessionStore.clear();
            // @lat: [[identity-and-access#Identity and access#Sessions, cookies and bearer tokens]]
            try {
                const consumerMod: { destroyConsumer?: () => void } = await import("../channels/consumer");
                consumerMod.destroyConsumer?.();
            } catch {
                // @lat: [[mobile-api-client-contract#Why a 401 also closes the WebSocket, and why that import is inline]]
            }
            authEvents.emit("unauthenticated");
        }
        throw new UnauthorizedError(envelope.code, envelope.message, envelope.details, res.status);
    }
    if (res.status === 429) {
        throw new RateLimitedError(
            envelope.code,
            envelope.message ?? "try again shortly",
            envelope.details,
            res.status,
        );
    }
    throw new ApiRequestError(envelope.code, envelope.message, envelope.details, res.status);
}

export const apiClient = {
    setLocaleId: (id: number | null) => localeOverride.set(id),

    // @lat: [[lazy-inertia-props#Mobile JSON omission is an explicit request]]
    get: <T>(path: string, opts?: Pick<RequestOptions, "signal" | "timeoutMs" | "headers">) =>
        request<T>(path, { ...opts }),

    post: <T>(path: string, body: unknown, opts?: { signal?: AbortSignal; timeoutMs?: number }) =>
        request<T>(path, { method: "POST", body, ...opts }),

    patch: <T>(path: string, body: unknown, opts?: { signal?: AbortSignal; timeoutMs?: number }) =>
        request<T>(path, { method: "PATCH", body, ...opts }),

    delete: (path: string, opts?: { signal?: AbortSignal; timeoutMs?: number }) =>
        request<void>(path, { method: "DELETE", ...opts }),
};
