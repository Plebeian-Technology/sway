import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
    installBrokenLocalStorage,
    installLocalStorage,
    removeLocalStorage,
} from "app/frontend/__tests__/__mocks__/local_storage";

const sentry = vi.hoisted(() => ({ captureMessage: vi.fn<() => void>() }));
vi.mock("@sentry/react", () => ({ captureMessage: sentry.captureMessage }));

/**
 // @lat: [[frontend-test-infrastructure-notes#reportOnce: resetting two separate limits]]
 */
const freshReportOnce = async () => {
    vi.resetModules();
    const { reportOnce } = await import("app/frontend/sway_utils/report_once");
    return reportOnce;
};

describe("reportOnce", () => {
    beforeEach(() => {
        sentry.captureMessage.mockClear();
        installLocalStorage();
    });

    afterEach(() => {
        vi.useRealTimers();
        removeLocalStorage();
    });

    it("sends the first message", async () => {
        const reportOnce = await freshReportOnce();

        expect(reportOnce("a-key", "a message")).toBe(true);
        expect(sentry.captureMessage).toHaveBeenCalledTimes(1);
    });

    it("files it under the key so every copy lands in one issue", async () => {
        const reportOnce = await freshReportOnce();
        reportOnce("a-key", "a message");

        expect(sentry.captureMessage).toHaveBeenCalledWith(
            "a message",
            expect.objectContaining({ fingerprint: ["a-key"], level: "error" }),
        );
    });

    it("stays quiet for the rest of the tab", async () => {
        const reportOnce = await freshReportOnce();
        reportOnce("a-key", "a message");
        reportOnce("a-key", "a message");
        reportOnce("a-key", "a message");

        expect(sentry.captureMessage).toHaveBeenCalledTimes(1);
    });

    it("stays quiet in a new tab while the window has not passed", async () => {
        const first = await freshReportOnce();
        first("a-key", "a message");

        // A new tab: memory is empty again, but storage still remembers.
        const second = await freshReportOnce();

        expect(second("a-key", "a message")).toBe(false);
        expect(sentry.captureMessage).toHaveBeenCalledTimes(1);
    });

    it("speaks again once the window has passed", async () => {
        const first = await freshReportOnce();
        first("a-key", "a message", { windowMs: 1000 });

        vi.useFakeTimers();
        vi.setSystemTime(Date.now() + 5000);

        const second = await freshReportOnce();

        expect(second("a-key", "a message", { windowMs: 1000 })).toBe(true);
        expect(sentry.captureMessage).toHaveBeenCalledTimes(2);
    });

    it("keeps different keys apart", async () => {
        const reportOnce = await freshReportOnce();
        reportOnce("key-one", "first");
        reportOnce("key-two", "second");

        expect(sentry.captureMessage).toHaveBeenCalledTimes(2);
    });

    it("still reports once per tab when storage refuses every call", async () => {
        installBrokenLocalStorage();
        const reportOnce = await freshReportOnce();

        expect(reportOnce("a-key", "a message")).toBe(true);
        expect(reportOnce("a-key", "a message")).toBe(false);
        expect(sentry.captureMessage).toHaveBeenCalledTimes(1);
    });

    it("still reports once per tab when there is no storage at all", async () => {
        removeLocalStorage();
        const reportOnce = await freshReportOnce();

        expect(reportOnce("a-key", "a message")).toBe(true);
        expect(reportOnce("a-key", "a message")).toBe(false);
        expect(sentry.captureMessage).toHaveBeenCalledTimes(1);
    });
});
