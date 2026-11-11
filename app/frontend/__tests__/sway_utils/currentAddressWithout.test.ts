// @lat: [[bill-creator-pipeline-controls-panel#Pipeline actions preserve the working address]]

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { currentAddressWithout } from "app/frontend/sway_utils/currentAddressWithout";
import { isQueryParamCleared, stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";

const at = (address: string) => window.history.replaceState({}, "", address);

const ORIGINAL = "/";

beforeEach(() => at(ORIGINAL));
afterEach(() => at(ORIGINAL));

describe("currentAddressWithout", () => {
    it("keeps every parameter the caller did not name", () => {
        at("/admin/bill_creator/12/pipeline?run_id=77&sway_locale_id=3");

        const address = currentAddressWithout(["selected_stages", "download_missing_assets"]);

        expect(address).toContain("run_id=77");
        expect(address).toContain("sway_locale_id=3");
    });

    it("keeps the path, which is where the bill and the tab live", () => {
        at("/admin/bill_creator/12/pipeline?run_id=77");

        expect(currentAddressWithout([])).toMatch(/^\/admin\/bill_creator\/12\/pipeline\?/);
    });

    // The other half, and the reason `owned` exists at all. Inertia's merge
    // KEEPS a parameter the visit's data leaves out, so a value the operator
    // has just cleared would come back off the old address.
    it("marks the parameters the caller is about to set for itself as cleared", () => {
        at("/admin/bill_creator/12/pipeline?run_id=77&download_missing_assets=0");

        const address = currentAddressWithout(["download_missing_assets"]);

        expect(isQueryParamCleared(address, "download_missing_assets")).toBe(true);
        expect(address).toContain("download_missing_assets=");
        expect(address).toContain("run_id=77");
        expect(stripClearedQueryParams(address)).toBe("/admin/bill_creator/12/pipeline?run_id=77");
    });

    it("marks an array parameter under the bracketed spelling as cleared", () => {
        at("/admin/bill_creator/12/pipeline?run_id=77&filter_ids%5B%5D=fetch-bills&filter_ids%5B%5D=fetch-law");

        const address = currentAddressWithout(["filter_ids"]);

        expect(isQueryParamCleared(address, "filter_ids")).toBe(true);
        expect(address).toContain("run_id=77");
        expect(stripClearedQueryParams(address)).toBe("/admin/bill_creator/12/pipeline?run_id=77");
    });

    it("returns a bare path when the address has no query at all", () => {
        at("/admin/bill_creator/new");

        expect(currentAddressWithout(["selected_stages"])).toBe("/admin/bill_creator/new");
    });
});
