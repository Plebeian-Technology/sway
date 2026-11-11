import { Platform } from "react-native";

import { dsnForThisPlatform, isLocalErrorCollectorDsn } from "../../src/observability/local_error_dsn";

const KEY = "abc123";

describe("isLocalErrorCollectorDsn", () => {
    it.each([
        ["localhost", `http://${KEY}@localhost:8482/1`],
        ["127.0.0.1", `http://${KEY}@127.0.0.1:8482/1`],
        ["the Android emulator's host", `http://${KEY}@10.0.2.2:8482/1`],
        ["no port", `http://${KEY}@localhost/1`],
    ])("accepts %s", (_name, dsn) => {
        expect(isLocalErrorCollectorDsn(dsn)).toBe(true);
    });

    // @lat: [[local-error-reporting-design#Why SwayLocalErrorDsn refuses rather than warns]]
    it.each([
        ["a hosted collector", `http://${KEY}@errors.example.com/1`],
        ["Sentry itself", `https://${KEY}@o123.ingest.sentry.io/1`],
        ["a phone reaching the dev machine over the network", `http://${KEY}@192.168.1.14:8482/1`],
        ["a lookalike host", `http://${KEY}@localhost.evil.example.com/1`],
    ])("refuses %s", (_name, dsn) => {
        expect(isLocalErrorCollectorDsn(dsn)).toBe(false);
    });

    it.each([
        ["undefined", undefined],
        ["empty", ""],
        ["not a DSN at all", "not a url"],
        ["missing the key", "http://localhost:8482/1"],
    ])("refuses %s, since it cannot be shown to be local", (_name, dsn) => {
        expect(isLocalErrorCollectorDsn(dsn)).toBe(false);
    });
});

describe("dsnForThisPlatform", () => {
    afterEach(() => {
        (Platform as { OS: string }).OS = "ios";
    });

    it("leaves the address alone on iOS, where the simulator shares the host loopback", () => {
        (Platform as { OS: string }).OS = "ios";

        expect(dsnForThisPlatform(`http://${KEY}@localhost:8482/1`)).toBe(`http://${KEY}@localhost:8482/1`);
    });

    it("rewrites localhost for Android, which reaches its host as 10.0.2.2", () => {
        (Platform as { OS: string }).OS = "android";

        expect(dsnForThisPlatform(`http://${KEY}@localhost:8482/1`)).toBe(`http://${KEY}@10.0.2.2:8482/1`);
    });

    it("rewrites 127.0.0.1 for Android too", () => {
        (Platform as { OS: string }).OS = "android";

        expect(dsnForThisPlatform(`http://${KEY}@127.0.0.1:8482/1`)).toBe(`http://${KEY}@10.0.2.2:8482/1`);
    });

    // @lat: [[local-error-reporting-design#Why SwayLocalErrorDsn refuses rather than warns]]
    it("leaves a host that is not loopback alone on Android", () => {
        (Platform as { OS: string }).OS = "android";

        expect(dsnForThisPlatform(`http://${KEY}@errors.example.com/1`)).toBe(`http://${KEY}@errors.example.com/1`);
    });

    it("does not touch a key that happens to contain the host name", () => {
        (Platform as { OS: string }).OS = "android";

        expect(dsnForThisPlatform("http://localhostkey@localhost:8482/1")).toBe("http://localhostkey@10.0.2.2:8482/1");
    });
});
