// @lat: [[client-caches-and-identity#Client caches and identity#The reload-reason record has to survive its own failures]]

import { beforeEach, describe, expect, it } from "vitest";

import { appendReloadReason, readReloadReasons, type IReloadReason } from "app/frontend/dev/reloadReasonStore";

const KEY = "sway.dev.reload_reasons";

const reason = (at: number): IReloadReason => ({ event: "vite:ws:disconnect", at, path: "/pipeline" });

beforeEach(() => window.sessionStorage.clear());

describe("readReloadReasons / appendReloadReason", () => {
    it("hands back what it stored", () => {
        appendReloadReason(window.sessionStorage, reason(1));
        appendReloadReason(window.sessionStorage, reason(2));

        expect(readReloadReasons(window.sessionStorage).map((r) => r.at)).toEqual([1, 2]);
    });

    it("keeps the ten newest and drops the rest", () => {
        for (let at = 1; at <= 14; at += 1) appendReloadReason(window.sessionStorage, reason(at));

        expect(readReloadReasons(window.sessionStorage).map((r) => r.at)).toEqual([5, 6, 7, 8, 9, 10, 11, 12, 13, 14]);
    });

    it("reads nothing at all as nothing recorded", () => {
        expect(readReloadReasons(window.sessionStorage)).toEqual([]);
    });

    // The key is a plain string in a store anything on the page can write to,
    // so what comes back is not guaranteed to be what this code put there.
    it("reads text that is not JSON as nothing recorded", () => {
        window.sessionStorage.setItem(KEY, "{not json");

        expect(readReloadReasons(window.sessionStorage)).toEqual([]);
    });

    it("drops entries of the wrong shape rather than handing them on", () => {
        window.sessionStorage.setItem(KEY, JSON.stringify([{ event: 7 }, reason(3), null]));

        expect(readReloadReasons(window.sessionStorage).map((r) => r.at)).toEqual([3]);
    });

    // A browser with storage turned off throws on every call. A diagnostic
    // that takes the page down with it is worse than no diagnostic.
    it("stays quiet when the browser refuses to store anything", () => {
        const refusing = {
            getItem: () => {
                throw new Error("storage is off");
            },
            setItem: () => {
                throw new Error("storage is off");
            },
        } as unknown as Storage;

        expect(() => appendReloadReason(refusing, reason(1))).not.toThrow();
        expect(readReloadReasons(refusing)).toEqual([]);
    });
});
