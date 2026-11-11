// @lat: [[dev-reload-reason-diagnostic#What reportWhyThePageReloaded.test.ts is checking]]

import { beforeEach, describe, expect, it } from "vitest";

import { readReloadReasons } from "app/frontend/dev/reloadReasonStore";
import { reportWhyThePageReloaded, type IHotEvents } from "app/frontend/dev/reportWhyThePageReloaded";

/** Stands in for Vite's dev client, which is absent under vitest. */
const fakeHot = () => {
    const listeners = new Map<string, () => void>();
    const hot: IHotEvents = { on: (event, listener) => listeners.set(event, () => listener(undefined)) };
    return { hot, fire: (event: string) => listeners.get(event)?.(), listens: () => [...listeners.keys()] };
};

beforeEach(() => {
    window.sessionStorage.clear();
    window.history.replaceState({}, "", "/admin/bill_creator/62/pipeline?run_id=7");
});

describe("reportWhyThePageReloaded", () => {
    // The exact strings matter and cannot be checked by anything else: Vite
    // raises these names, and a listener on a name Vite never raises is
    // indistinguishable from a working one until a reload goes unexplained.
    it("listens for all three events Vite raises before a reload", () => {
        const vite = fakeHot();

        reportWhyThePageReloaded(vite.hot);

        expect(vite.listens()).toEqual(["vite:ws:disconnect", "vite:beforeFullReload", "vite:error"]);
    });

    it("writes down the event, the time and where the page was", () => {
        const vite = fakeHot();
        reportWhyThePageReloaded(vite.hot);

        vite.fire("vite:ws:disconnect");

        const [recorded] = readReloadReasons(window.sessionStorage);
        expect(recorded.event).toBe("vite:ws:disconnect");
        expect(recorded.path).toBe("/admin/bill_creator/62/pipeline?run_id=7");
        expect(recorded.at).toBeGreaterThan(0);
    });

    it("records each event under its own name", () => {
        const vite = fakeHot();
        reportWhyThePageReloaded(vite.hot);

        vite.fire("vite:error");
        vite.fire("vite:beforeFullReload");

        expect(readReloadReasons(window.sessionStorage).map((r) => r.event)).toEqual([
            "vite:error",
            "vite:beforeFullReload",
        ]);
    });

    // A built bundle has no import.meta.hot. Registering nothing there is the
    // whole reason this is safe to ship.
    it("does nothing when there is no dev server", () => {
        expect(() => reportWhyThePageReloaded(undefined)).not.toThrow();
        expect(readReloadReasons(window.sessionStorage)).toEqual([]);
    });
});
