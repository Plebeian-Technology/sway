// @lat: [[bill-creator-pipeline-controls-panel#Why an empty stage selection is spelled out on the wire]]

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
    INTENTIONAL_EMPTY_LIST_PARAMETERS,
    addressWithEmptyList,
    isIntentionalEmptyListParameter,
} from "app/frontend/sway_utils/addressWithEmptyList";
import { stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";

const at = (address: string) => window.history.replaceState({}, "", address);

const ORIGINAL = "/";

beforeEach(() => at(ORIGINAL));
afterEach(() => at(ORIGINAL));

describe("addressWithEmptyList", () => {
    it("writes the name with an empty value", () => {
        expect(addressWithEmptyList("/admin/bill_creator/12/pipeline", "selected_stages")).toBe(
            "/admin/bill_creator/12/pipeline?selected_stages=",
        );
    });

    it("keeps every parameter already on the address", () => {
        const address = addressWithEmptyList(
            "/admin/bill_creator/12/pipeline?run_id=77&sway_locale_id=3",
            "selected_stages",
        );

        expect(address).toContain("run_id=77");
        expect(address).toContain("sway_locale_id=3");
        expect(address).toMatch(/[?&]selected_stages=(&|$)/);
    });

    it("keeps the path, which is where the bill and the tab live", () => {
        expect(addressWithEmptyList("/admin/bill_creator/12/pipeline?run_id=77", "selected_stages")).toMatch(
            /^\/admin\/bill_creator\/12\/pipeline\?/,
        );
    });

    // The empty value has to REPLACE a value already there, not sit beside it.
    // Two `selected_stages` pairs would leave Rails reading the first one, which
    // is the stale list the operator has just cleared.
    it("replaces a value the address was already carrying", () => {
        const address = addressWithEmptyList(
            "/admin/bill_creator/12/pipeline?selected_stages=fetch-bills&run_id=77",
            "selected_stages",
        );

        expect(address.match(/selected_stages=/g)).toHaveLength(1);
        expect(address).not.toContain("fetch-bills");
    });

    it("takes the bracket spelling off, not only the scalar one", () => {
        const address = addressWithEmptyList(
            "/admin/bill_creator/12/pipeline?selected_stages%5B%5D=fetch-bills&run_id=77",
            "selected_stages",
        );

        expect(address).not.toContain("selected_stages%5B%5D");
        expect(address).not.toContain("selected_stages[]");
        expect(address).not.toContain("fetch-bills");
        expect(address).toMatch(/[?&]selected_stages=(&|$)/);
        expect(address).toContain("run_id=77");
    });

    // The address is relative and this helper must keep it relative: the visit
    // is handed a path, not an absolute URL, so an origin leaking in would send
    // the router somewhere else.
    it("returns a relative address, never the origin", () => {
        at("/admin/bill_creator/12/pipeline");

        expect(addressWithEmptyList("/admin/bill_creator/12/pipeline", "selected_stages")).not.toContain(
            window.location.origin,
        );
    });
});

describe("isIntentionalEmptyListParameter", () => {
    it("recognizes selected_stages and legacy stages in intentional scalar empty-list form", () => {
        expect(INTENTIONAL_EMPTY_LIST_PARAMETERS).toContain("selected_stages");
        expect(INTENTIONAL_EMPTY_LIST_PARAMETERS).toContain("stages");
        expect(isIntentionalEmptyListParameter("selected_stages")).toBe(true);
        expect(isIntentionalEmptyListParameter("stages")).toBe(true);
    });

    it("rejects bracketed spellings so cleared bracketed parameters can be stripped", () => {
        expect(isIntentionalEmptyListParameter("selected_stages[]")).toBe(false);
        expect(isIntentionalEmptyListParameter("selected_stages%5B%5D")).toBe(false);
        expect(isIntentionalEmptyListParameter("stages[]")).toBe(false);
        expect(isIntentionalEmptyListParameter("stages%5B%5D")).toBe(false);
    });

    it("rejects generic parameters", () => {
        expect(isIntentionalEmptyListParameter("run_id")).toBe(false);
        expect(isIntentionalEmptyListParameter("search")).toBe(false);
        expect(isIntentionalEmptyListParameter("page")).toBe(false);
        expect(isIntentionalEmptyListParameter("sort")).toBe(false);
        expect(isIntentionalEmptyListParameter("download_missing_assets")).toBe(false);
    });
});

describe("addressWithEmptyList stripped survival", () => {
    it("preserves selected_stages= when passed through stripClearedQueryParams", () => {
        const address = addressWithEmptyList("/admin/bill_creator/42/pipeline?run_id=77", "selected_stages");
        expect(stripClearedQueryParams(address)).toBe("/admin/bill_creator/42/pipeline?run_id=77&selected_stages=");
    });

    it("preserves stages= when passed through stripClearedQueryParams", () => {
        const address = addressWithEmptyList("/admin/bill_creator/42/pipeline?search=test", "stages");
        expect(stripClearedQueryParams(address)).toBe("/admin/bill_creator/42/pipeline?search=test&stages=");
    });
});
