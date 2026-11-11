// An Inertia redirect to a valid page is a SUCCESSFUL visit, so onSuccess fires for a
// destroyed bill or lapsed admin session too, not only a save that worked (C20-05).

import { describe, expect, it } from "vitest";
import { landedOnBillCreator } from "app/frontend/components/admin/creator/billCreatorLanding";

describe("landedOnBillCreator", () => {
    it("accepts every tab of the bill's own Bill Creator", () => {
        expect(landedOnBillCreator("/admin/bill_creator/7/creator?event_key=legislator_votes", 7)).toBe(true);
        expect(landedOnBillCreator("/admin/bill_creator/7/summary", 7)).toBe(true);
        expect(landedOnBillCreator("/admin/bill_creator/7", 7)).toBe(true);
        expect(landedOnBillCreator("/admin/bill_creator/7?saved=1", 7)).toBe(true);
        expect(landedOnBillCreator("/admin/bill_creator/7#positions", 7)).toBe(true);
    });

    // The two redirects BillsController#update and verify_is_sway_admin take.
    it("refuses the pages a refused write is sent to", () => {
        expect(landedOnBillCreator("/admin/bill_creator/new", 7)).toBe(false);
        expect(landedOnBillCreator("/", 7)).toBe(false);
    });

    // A bare startsWith would read /admin/bill_creator/12 as bill 1's page, so
    // saving bill 1 while looking at bill 12 would toast a success it had no
    // grounds for.
    it("does not read one bill's page as another's on a shared id prefix", () => {
        expect(landedOnBillCreator("/admin/bill_creator/12/summary", 1)).toBe(false);
        expect(landedOnBillCreator("/admin/bill_creator/1/summary", 12)).toBe(false);
    });
});
