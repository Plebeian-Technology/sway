import type { ErrorEvent } from "@sentry/react";
import * as Sentry from "@sentry/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SentryUtil } from "app/frontend/sway_utils/sentry";

vi.mock("@sentry/react", () => ({
    init: vi.fn<(options?: unknown) => void>(),
    replayIntegration: vi.fn<(options?: unknown) => unknown>(),
    browserTracingIntegration: vi.fn<() => unknown>(),
    captureException: vi.fn<(err?: unknown) => string>(),
    captureMessage: vi.fn<(msg?: unknown) => string>(),
}));

describe("SentryUtil.beforeSend", () => {
    const makeEvent = (value: string, frames?: unknown[]): ErrorEvent =>
        ({
            event_id: "test123",
            exception: {
                values: [
                    {
                        type: "Error",
                        value,
                        stacktrace: frames ? { frames } : undefined,
                    },
                ],
            },
        }) as unknown as ErrorEvent;

    beforeEach(() => {
        vi.clearAllMocks();
    });

    afterEach(() => {
        vi.unstubAllEnvs();
    });

    it("passes beforeSend to Sentry.init when VITE_SENTRY_DSN is present in production", async () => {
        vi.stubEnv("MODE", "production");
        vi.stubEnv("VITE_SENTRY_DSN", "https://key@sentry.io/123");

        await SentryUtil.init();

        expect(Sentry.init).toHaveBeenCalledWith(
            expect.objectContaining({
                dsn: "https://key@sentry.io/123",
                beforeSend: expect.any(Function),
            }),
        );
        expect(Sentry.replayIntegration).toHaveBeenCalledWith({
            maskAllText: true,
            blockAllMedia: true,
        });
    });

    it("returns null when the exception value starts with 'Unable to preload CSS for '", () => {
        const event = makeEvent("Unable to preload CSS for https://sway.vote/vite/assets/Home-DQ3q4JL_.css");
        expect(SentryUtil.beforeSend(event)).toBeNull();
    });

    it.each(["Load failed", "Failed to fetch", "NetworkError when attempting to fetch resource"])(
        "returns null for transient network error: %s",
        (msg) => {
            const event = makeEvent(msg);
            expect(SentryUtil.beforeSend(event)).toBeNull();
        },
    );

    it("returns null for synthetic undefined or null error without stack frames", () => {
        const eventUndefined = makeEvent("undefined");
        expect(SentryUtil.beforeSend(eventUndefined)).toBeNull();

        const eventNull = makeEvent("null");
        expect(SentryUtil.beforeSend(eventNull)).toBeNull();

        const eventEmpty = makeEvent("");
        expect(SentryUtil.beforeSend(eventEmpty)).toBeNull();
    });

    it("preserves genuine errors even when value is undefined if stack frames exist", () => {
        const event = makeEvent("undefined", [{ filename: "app.js", lineno: 10 }]);
        expect(SentryUtil.beforeSend(event)).toEqual(event);
    });

    it("returns the event unchanged for genuine application errors", () => {
        const event = makeEvent("TypeError: Cannot read properties of undefined");
        expect(SentryUtil.beforeSend(event)).toEqual(event);
    });

    it("scrubs bearer_token, street, and email values from forwarded events via scrubErrorEvent", () => {
        const event = {
            ...makeEvent("Error for user voter@example.com"),
            extra: {
                bearer_token: "secret-bearer-token",
                street: "123 E Fayette St",
                note: "contact voter@example.com",
            },
        } as unknown as ErrorEvent;

        const scrubbed = SentryUtil.beforeSend(event);
        expect(scrubbed).not.toBeNull();
        expect(scrubbed?.exception?.values?.[0]?.value).toBe("Error for user [FILTERED_EMAIL]");
        expect(scrubbed?.extra).toEqual({
            bearer_token: "[FILTERED]",
            street: "[FILTERED]",
            note: "contact [FILTERED_EMAIL]",
        });
    });

    it("wires window.console.error safely in production without capturing null or undefined", async () => {
        vi.stubEnv("MODE", "production");
        await SentryUtil.init();

        window.console.error(null);
        window.console.error(undefined);
        window.console.error();
        expect(Sentry.captureException).not.toHaveBeenCalled();
        expect(Sentry.captureMessage).not.toHaveBeenCalled();

        const err = new Error("Something went wrong");
        window.console.error(err);
        expect(Sentry.captureException).toHaveBeenCalledWith(err, undefined);

        const breakErr = new Error("Something broke");
        window.console.error(null, breakErr);
        expect(Sentry.captureException).toHaveBeenCalledWith(breakErr, undefined);

        const nestedErr = new Error("Failed to load");
        window.console.error("Context message", nestedErr);
        expect(Sentry.captureException).toHaveBeenCalledWith(nestedErr, {
            extra: { args: ["Context message"] },
        });

        window.console.error("Notice string message", { detail: 123 });
        expect(Sentry.captureMessage).toHaveBeenCalledWith('Notice string message {"detail":123}');
    });

    it("captures non-Error objects via captureMessage in production", async () => {
        vi.stubEnv("MODE", "production");
        await SentryUtil.init();

        window.console.error({ error: "failed" });
        expect(Sentry.captureMessage).toHaveBeenCalledWith('{"error":"failed"}');
    });
});
