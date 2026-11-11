import { describe, expect, it } from "vitest";

import {
    briefSummary,
    hasLegalClause,
    shortBillTitle,
    splitBillTitle,
} from "app/frontend/components/bill/sway_utils/billTitle";

describe("splitBillTitle", () => {
    it("splits a hyphen-separated title into headline and deck", () => {
        expect(splitBillTitle("Clean Energy Act - modernizing the grid")).toEqual({
            headline: "Clean Energy Act",
            deck: "modernizing the grid",
        });
    });

    it("splits on an en dash", () => {
        expect(splitBillTitle("Clean Energy Act – modernizing the grid")).toEqual({
            headline: "Clean Energy Act",
            deck: "modernizing the grid",
        });
    });

    it("splits on an em dash", () => {
        expect(splitBillTitle("Clean Energy Act — modernizing the grid")).toEqual({
            headline: "Clean Energy Act",
            deck: "modernizing the grid",
        });
    });

    it("drops the 'FOR the purpose of' legal boilerplate", () => {
        expect(splitBillTitle("Property Tax Credit FOR the purpose of altering the credit")).toEqual({
            headline: "Property Tax Credit",
            deck: null,
        });
    });

    it("matches the boilerplate case-insensitively", () => {
        expect(splitBillTitle("Property Tax Credit for the purpose of altering the credit").headline).toBe(
            "Property Tax Credit",
        );
    });

    it("takes the headline and deck from the text before the boilerplate", () => {
        expect(splitBillTitle("Budget Bill - fiscal year 2026 FOR the purpose of appropriating funds")).toEqual({
            headline: "Budget Bill",
            deck: "fiscal year 2026",
        });
    });

    it("returns a null deck when there is no dash", () => {
        expect(splitBillTitle("A Resolution Honoring Volunteers")).toEqual({
            headline: "A Resolution Honoring Volunteers",
            deck: null,
        });
    });

    it("splits on the first dash only, keeping later dashes in the deck", () => {
        expect(splitBillTitle("Transit Act - phase one - downtown corridor")).toEqual({
            headline: "Transit Act",
            deck: "phase one - downtown corridor",
        });
    });

    it("trims surrounding whitespace", () => {
        expect(splitBillTitle("  Spacious Title  ")).toEqual({ headline: "Spacious Title", deck: null });
    });

    it("returns an empty headline for an empty string", () => {
        expect(splitBillTitle("")).toEqual({ headline: "", deck: null });
    });
});

describe("briefSummary", () => {
    it("strips NEWLINE and ENDING pipeline markers", () => {
        expect(briefSummary("First line.NEWLINESecond line.ENDING", 240)).toBe("First line. Second line.");
    });

    it("collapses runs of whitespace to a single space", () => {
        expect(briefSummary("too      many\n\nspaces", 240)).toBe("too many spaces");
    });

    it("truncates to the requested maximum length", () => {
        expect(briefSummary("abcdefghij", 4)).toBe("abcd");
    });

    it("returns an empty string for an undefined summary", () => {
        expect(briefSummary(undefined, 240)).toBe("");
    });

    it("returns an empty string for an empty summary", () => {
        expect(briefSummary("", 240)).toBe("");
    });
});

// @lat: [[bill-title-display#How a bill's title is shown#Where only the subject is shown]]
describe("shortBillTitle", () => {
    it("joins the subject and the part after it with one separator", () => {
        expect(shortBillTitle("Rezoning – 2400 Boston Street")).toBe("Rezoning — 2400 Boston Street");
    });

    it("returns the subject alone when there is no second part", () => {
        expect(shortBillTitle("A Resolution Honoring Volunteers")).toBe("A Resolution Honoring Volunteers");
    });

    it("drops the legislature's own wording", () => {
        expect(shortBillTitle("Property Tax Credit FOR the purpose of altering the credit")).toBe(
            "Property Tax Credit",
        );
    });
});

// Tells a page whether its heading is showing the whole stored title or only
// the front of it, so a bill with nothing extra gets no empty block.
describe("hasLegalClause", () => {
    it("is true when the title carries the clause", () => {
        expect(hasLegalClause("Zoning Code – Modifications\n\nFOR the purpose of amending provisions")).toBe(true);
    });

    it("is false for a title that is only its subject", () => {
        expect(hasLegalClause("Rezoning – 2400 Boston Street")).toBe(false);
    });

    it("ignores capitalisation, the way splitBillTitle does", () => {
        expect(hasLegalClause("Property Tax Credit for the purpose of altering the credit")).toBe(true);
    });
});
