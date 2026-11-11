// @lat: [[mobile-test-infrastructure-notes#sentry.test.ts: mocking expo-constants and importing initSentry once]]
jest.mock("expo-constants", () => ({ __esModule: true, default: { expoConfig: { extra: {} } } }));

import * as Sentry from "@sentry/react-native";
import Constants from "expo-constants";

import { initSentry } from "../src/observability/sentry";

// @lat: [[mobile-test-infrastructure-notes#sentry.test.ts: mocking expo-constants and importing initSentry once]]
describe("initSentry in development", () => {
    const setExtra = (extra: Record<string, unknown>) => {
        (Constants.expoConfig as { extra: Record<string, unknown> }).extra = extra;
    };

    beforeEach(() => {
        (Sentry.init as jest.Mock).mockClear();
        setExtra({});
    });

    it("does not initialize when no collector address is set", () => {
        initSentry();

        expect(Sentry.init).not.toHaveBeenCalled();
    });

    it("initializes against a collector on the dev machine", () => {
        setExtra({ rustrakDsn: "http://abc123@localhost:8482/1" });

        initSentry();

        expect(Sentry.init).toHaveBeenCalledWith(expect.objectContaining({ dsn: "http://abc123@localhost:8482/1" }));
    });

    // @lat: [[local-error-reporting-design#Why SwayLocalErrorDsn refuses rather than warns]]
    it("refuses an address that is not on the dev machine", () => {
        setExtra({ rustrakDsn: "http://abc123@errors.example.com/1" });

        initSentry();

        expect(Sentry.init).not.toHaveBeenCalled();
    });

    it("never falls back to the production Sentry address in development", () => {
        setExtra({ sentryDsn: "https://key@o1.ingest.sentry.io/1" });

        initSentry();

        expect(Sentry.init).not.toHaveBeenCalled();
    });

    it("asks for no tracing, which the collector discards anyway", () => {
        setExtra({ rustrakDsn: "http://abc123@localhost:8482/1" });

        initSentry();

        expect(Sentry.init).toHaveBeenCalledWith(expect.objectContaining({ tracesSampleRate: 0 }));
    });

    it("scrubs an event through beforeSend", () => {
        setExtra({ rustrakDsn: "http://abc123@localhost:8482/1" });

        initSentry();

        const { beforeSend } = (Sentry.init as jest.Mock).mock.calls[0][0];
        const scrubbed = beforeSend({ message: "reach planted.person@example-not-real.org" });

        expect(scrubbed.message).toBe("reach [FILTERED_EMAIL]");
    });
});

describe("initSentry in production", () => {
    const devGlobal = globalThis as { __DEV__?: boolean };
    let originalDev: boolean | undefined;

    const setExtra = (extra: Record<string, unknown>) => {
        (Constants.expoConfig as { extra: Record<string, unknown> }).extra = extra;
    };

    beforeEach(() => {
        originalDev = devGlobal.__DEV__;
        devGlobal.__DEV__ = false;
        (Sentry.init as jest.Mock).mockClear();
        setExtra({});
    });

    afterEach(() => {
        devGlobal.__DEV__ = originalDev;
    });

    it("passes sendDefaultPii: false and a beforeSend callback that scrubs sensitive fields via scrubErrorEvent", () => {
        setExtra({ sentryDsn: "https://key@o1.ingest.sentry.io/1" });

        initSentry();

        expect(Sentry.init).toHaveBeenCalledWith(
            expect.objectContaining({
                dsn: "https://key@o1.ingest.sentry.io/1",
                sendDefaultPii: false,
                beforeSend: expect.any(Function),
            }),
        );

        const { beforeSend } = (Sentry.init as jest.Mock).mock.calls[0][0];
        const scrubbed = beforeSend({
            message: "Error for voter@example.org",
            extra: {
                bearer_token: "secret-token",
                street: "100 Holliday St",
            },
        });

        expect(scrubbed.message).toBe("Error for [FILTERED_EMAIL]");
        expect(scrubbed.extra).toEqual({
            bearer_token: "[FILTERED]",
            street: "[FILTERED]",
        });
    });
});
