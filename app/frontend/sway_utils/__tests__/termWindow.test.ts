import { describe, expect, it } from "vitest";

import { formatTermWindow } from "app/frontend/sway_utils/termWindow";

describe("formatTermWindow", () => {
    it("shows the election cycle when Sway holds no real days", () => {
        expect(formatTermWindow({ term_start_year: 2025, term_end_year: 2027 })).toEqual("2025–2027");
    });

    // The point of the whole thing: somebody who left in July 2026 held a seat
    // whose cycle runs to 2027, and the years alone say they held all of it.
    it("shows the day somebody left, in place of the year at that end", () => {
        expect(
            formatTermWindow({
                term_start_year: 2021,
                term_end_year: 2027,
                ended_on: "2026-07-11",
            }),
        ).toEqual("2021–Jul 11, 2026");
    });

    it("shows the day somebody arrived", () => {
        expect(
            formatTermWindow({
                term_start_year: 2025,
                term_end_year: 2027,
                began_on: "2025-03-04",
            }),
        ).toEqual("Mar 4, 2025–2027");
    });

    it("shows both days when it holds both", () => {
        expect(
            formatTermWindow({
                term_start_year: 2025,
                term_end_year: 2027,
                began_on: "2025-03-04",
                ended_on: "2026-01-05",
            }),
        ).toEqual("Mar 4, 2025–Jan 5, 2026");
    });

    // A stored day has no time in it. Read as midnight UTC and printed in a
    // zone west of London, it comes out as the day before — so Greene's last
    // day would read Jan 4 in Baltimore. Formatting in UTC keeps the day the
    // one the database holds.
    it("prints the day the database holds, not the day before", () => {
        const original = process.env.TZ;
        process.env.TZ = "America/New_York";
        try {
            expect(formatTermWindow({ term_start_year: 2025, term_end_year: 2027, ended_on: "2026-01-05" })).toEqual(
                "2025–Jan 5, 2026",
            );
        } finally {
            process.env.TZ = original;
        }
    });

    // What the pages already did with a legislator holding no terms: draw
    // nothing, rather than half a window.
    it("says nothing when either end is unknown", () => {
        expect(formatTermWindow({ term_start_year: 2025, term_end_year: null })).toBeNull();
        expect(formatTermWindow({})).toBeNull();
        expect(formatTermWindow(null)).toBeNull();
    });

    // A day is enough on its own; the year at that end is never needed.
    it("uses a real day even when its year is missing", () => {
        expect(formatTermWindow({ term_start_year: null, term_end_year: 2027, began_on: "2025-03-04" })).toEqual(
            "Mar 4, 2025–2027",
        );
    });
});
