import { describe, expect, it } from "vitest";

import categoryFilterHref from "app/frontend/sway_utils/categoryFilterHref";

describe("categoryFilterHref", () => {
    it("writes the selected categories as one comma-separated parameter", () => {
        expect(categoryFilterHref(["Police", "Health"], "/bills", "")).toBe("/bills?categories=Police%2CHealth");
    });

    it("drops the parameter entirely when nothing is selected", () => {
        expect(categoryFilterHref([], "/bills", "?categories=Police")).toBe("/bills");
    });

    // The Clear all control's whole job: put the reader back on the full list
    // without moving them to a different page, order or search.
    it("leaves every other parameter alone when it clears the categories", () => {
        expect(categoryFilterHref([], "/bills", "?categories=Police%2CHealth&page=3&sort=title&search=tax")).toBe(
            "/bills?page=3&sort=title&search=tax",
        );
    });

    it("replaces a previous selection rather than adding to it", () => {
        expect(categoryFilterHref(["Health"], "/bills", "?categories=Police&page=2")).toBe(
            "/bills?categories=Health&page=2",
        );
    });
});
