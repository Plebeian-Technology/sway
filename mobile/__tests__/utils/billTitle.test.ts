import { splitBillTitle, shortBillTitle, billHeadline, hasMoreThanHeadline } from "../../src/utils/billTitle";

describe("splitBillTitle", () => {
    test("splits hyphen deck", () => {
        expect(splitBillTitle("Clean Energy Act - modernizing the grid")).toEqual({
            headline: "Clean Energy Act",
            deck: "modernizing the grid",
        });
    });

    test("splits en-dash deck", () => {
        expect(splitBillTitle("Clean Energy Act – modernizing the grid")).toEqual({
            headline: "Clean Energy Act",
            deck: "modernizing the grid",
        });
    });

    test("splits em-dash deck", () => {
        expect(splitBillTitle("Clean Energy Act — modernizing the grid")).toEqual({
            headline: "Clean Energy Act",
            deck: "modernizing the grid",
        });
    });

    test("strips 'FOR the purpose of' clause", () => {
        expect(splitBillTitle("Property Tax Credit FOR the purpose of altering the credit")).toEqual({
            headline: "Property Tax Credit",
            deck: null,
        });
    });

    test("strips case-insensitive 'for the purpose of' clause", () => {
        expect(splitBillTitle("Property Tax Credit for the purpose of altering the credit")).toEqual({
            headline: "Property Tax Credit",
            deck: null,
        });
    });

    test("strips clause and preserves deck before it", () => {
        expect(splitBillTitle("Budget Bill - fiscal year 2026 FOR the purpose of appropriating funds")).toEqual({
            headline: "Budget Bill",
            deck: "fiscal year 2026",
        });
    });

    test("handles plain titles without clauses or dashes", () => {
        expect(splitBillTitle("A Resolution Honoring Volunteers")).toEqual({
            headline: "A Resolution Honoring Volunteers",
            deck: null,
        });
    });

    test("handles empty and whitespace-only strings", () => {
        expect(splitBillTitle("")).toEqual({ headline: "", deck: null });
        expect(splitBillTitle("   ")).toEqual({ headline: "", deck: null });
    });
});

describe("shortBillTitle", () => {
    test("formats with en-dash when deck is present", () => {
        expect(shortBillTitle("Clean Energy Act - modernizing the grid")).toBe(
            "Clean Energy Act — modernizing the grid",
        );
    });

    test("returns headline when no deck is present", () => {
        expect(shortBillTitle("Property Tax Credit FOR the purpose of altering the credit")).toBe(
            "Property Tax Credit",
        );
    });
});

describe("billHeadline", () => {
    test("returns headline for complex legal title", () => {
        expect(
            billHeadline(
                "Historic Preservation – Conservation Districts – Establishment\n\nFOR the purpose of establishing Conservation Districts",
            ),
        ).toBe("Historic Preservation");
    });

    test("returns empty string for null and undefined", () => {
        expect(billHeadline(null)).toBe("");
        expect(billHeadline(undefined)).toBe("");
        expect(billHeadline("")).toBe("");
    });
});

describe("hasMoreThanHeadline", () => {
    test("is true when the title carries a deck after a dash", () => {
        expect(hasMoreThanHeadline("Clean Energy Act - modernizing the grid")).toBe(true);
        expect(hasMoreThanHeadline("Clean Energy Act – modernizing the grid")).toBe(true);
    });

    test("is true when the title carries the enacting clause", () => {
        expect(hasMoreThanHeadline("Property Tax Credit FOR the purpose of altering the credit")).toBe(true);
        expect(hasMoreThanHeadline("Budget Bill - fiscal year 2026 FOR the purpose of appropriating funds")).toBe(true);
    });

    test("is false for a single phrase, whatever the surrounding whitespace", () => {
        expect(hasMoreThanHeadline("A Resolution Honoring Volunteers")).toBe(false);
        expect(hasMoreThanHeadline("  A Resolution Honoring Volunteers \n")).toBe(false);
    });

    test("is false for an empty title", () => {
        expect(hasMoreThanHeadline("")).toBe(false);
        expect(hasMoreThanHeadline("   ")).toBe(false);
    });
});
