import { describe, expect, it } from "vitest";
import { isLocalErrorCollectorDsn } from "app/frontend/sway_utils/local_error_dsn";

// @lat: [[browser-error-reporting#Browser error reporting#Development reports stay on this machine]]
describe("isLocalErrorCollectorDsn", () => {
    const publicId = "dsnpublicid";

    describe("addresses on this machine", () => {
        it.each([
            ["localhost", `http://${publicId}@localhost:8482/1`],
            ["127.0.0.1", `http://${publicId}@127.0.0.1:8482/1`],
            ["IPv6 loopback", `http://${publicId}@[::1]:8482/1`],
            ["the docker host alias", `http://${publicId}@host.docker.internal:8482/1`],
            ["the compose service name", `http://${publicId}@rustrak:8080/1`],
        ])("accepts %s", (_name, dsn) => {
            expect(isLocalErrorCollectorDsn(dsn)).toBe(true);
        });

        it("accepts regardless of how the host is capitalised", () => {
            expect(isLocalErrorCollectorDsn(`http://${publicId}@LOCALHOST:8482/1`)).toBe(true);
        });
    });

    describe("addresses that are not this machine", () => {
        it("refuses a hosted collector", () => {
            expect(isLocalErrorCollectorDsn(`https://${publicId}@errors.example.com/1`)).toBe(false);
        });

        it("refuses Sentry's own ingest host, which is the likeliest paste", () => {
            expect(isLocalErrorCollectorDsn(`https://${publicId}@o123.ingest.us.sentry.io/456`)).toBe(false);
        });

        // An `includes` check instead of an exact match would allow these.
        it("refuses a host that only looks local", () => {
            expect(isLocalErrorCollectorDsn(`http://${publicId}@localhost.evil.example.com/1`)).toBe(false);
            expect(isLocalErrorCollectorDsn(`http://${publicId}@notlocalhost/1`)).toBe(false);
            expect(isLocalErrorCollectorDsn(`http://${publicId}@127.0.0.1.evil.example.com/1`)).toBe(false);
        });

        it("refuses another machine on the same network", () => {
            expect(isLocalErrorCollectorDsn(`http://${publicId}@192.168.1.50:8482/1`)).toBe(false);
        });
    });

    describe("nothing usable", () => {
        it.each([
            ["undefined", undefined],
            ["an empty string", ""],
            ["something that is not a URL", "not-a-dsn"],
        ])("refuses %s", (_name, dsn) => {
            expect(isLocalErrorCollectorDsn(dsn)).toBe(false);
        });
    });
});
