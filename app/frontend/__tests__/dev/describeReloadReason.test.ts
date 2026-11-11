// @lat: [[dev-reload-reason-diagnostic#What describeReloadReason.test.ts is checking]]

import { describe, expect, it } from "vitest";

import { describeReloadReason } from "app/frontend/dev/describeReloadReason";
import type { IReloadReason } from "app/frontend/dev/reloadReasonStore";

const LOADED_AT_EPOCH_MS = 1_770_000_000_000;

const reason = (event: string, secondsBefore: number): IReloadReason => ({
    event,
    at: LOADED_AT_EPOCH_MS - secondsBefore * 1000,
    path: "/admin/bill_creator/62/pipeline",
});

describe("describeReloadReason", () => {
    it("says nothing when the browser navigated rather than reloaded", () => {
        expect(describeReloadReason([reason("vite:ws:disconnect", 1)], LOADED_AT_EPOCH_MS, false)).toBeNull();
    });

    it("names the dropped connection, in words that do not assume Vite", () => {
        const message = describeReloadReason([reason("vite:ws:disconnect", 2)], LOADED_AT_EPOCH_MS, true);

        expect(message).toContain("reloaded itself");
        expect(message).toContain("connection to the dev server dropped");
        expect(message).toContain("vite:ws:disconnect");
        expect(message).toContain("/admin/bill_creator/62/pipeline");
    });

    it("distinguishes a reload the dev server asked every page for", () => {
        const message = describeReloadReason([reason("vite:beforeFullReload", 1)], LOADED_AT_EPOCH_MS, true);

        expect(message).toContain("told every open page to reload");
    });

    // The finding this whole instrument exists to make possible. An empty
    // record is not "no information" — it RULES THE DEV SERVER OUT, which is
    // the half of the question that was unanswerable before.
    it("says the dev server was not responsible when it announced nothing", () => {
        const message = describeReloadReason([], LOADED_AT_EPOCH_MS, true);

        expect(message).toContain("it was not the dev server");
        expect(message).not.toContain("reloaded itself");
    });

    // Without this the record would keep accusing the dev server of every
    // later reload, because the entry never expires.
    it("does not blame an event from too long before this page loaded", () => {
        const message = describeReloadReason([reason("vite:ws:disconnect", 120)], LOADED_AT_EPOCH_MS, true);

        expect(message).toContain("it was not the dev server");
    });

    // A reason recorded AFTER this page loaded belongs to a reload that has
    // not happened yet, so it cannot explain this one.
    it("ignores a reason this page recorded itself", () => {
        const later: IReloadReason = { event: "vite:error", at: LOADED_AT_EPOCH_MS + 5000, path: "/x" };

        expect(describeReloadReason([later], LOADED_AT_EPOCH_MS, true)).toContain("it was not the dev server");
    });

    it("reports the last reason when several arrived", () => {
        const message = describeReloadReason(
            [reason("vite:error", 8), reason("vite:ws:disconnect", 3)],
            LOADED_AT_EPOCH_MS,
            true,
        );

        expect(message).toContain("connection to the dev server dropped");
    });
});
