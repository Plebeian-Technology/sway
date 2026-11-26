// @lat: [[mobile-bill-surface-components-design#DistrictVotesPanel]]
import {
    districtMajority,
    isVoteComparisonSuppressed,
    representativesText,
    selectDistrictVotes,
} from "../../src/utils/districtVotes";

// Rows in the shape BillScoreDistrictResource sends: no district id, no counts, region_code beside name and number.
const scoreRow = (
    number: number | null,
    name: string,
    regionCode: string | null,
    forPercent: number,
    againstPercent: number = 100 - forPercent,
) => ({
    bill_score_id: 9,
    district: { name, number, region_code: regionCode },
    comparison_suppressed: false,
    for_percent: forPercent,
    against_percent: againstPercent,
    at_large: false,
});

const READER = { name: "3A", number: 3, region_code: "A" };

describe("selectDistrictVotes", () => {
    test("returns nothing for a missing or empty district list", () => {
        for (const input of [null, undefined, []]) {
            const result = selectDistrictVotes(input, []);
            expect(result.rows).toEqual([]);
            expect(result.readerRows).toEqual([]);
        }
    });

    test("skips the at-large district (number 0) and sorts the rest by number", () => {
        const result = selectDistrictVotes(
            [scoreRow(10, "MD10", "MD", 1, 2), scoreRow(0, "MD0", "MD", 99, 99), scoreRow(2, "MD2", "MD", 3, 4)],
            [],
        );
        expect(result.rows.map((r) => r.number)).toEqual([2, 10]);
    });

    test("a district list holding only the at-large district has no rows", () => {
        const result = selectDistrictVotes([scoreRow(0, "MD0", "MD", 5, 1)], []);
        expect(result.rows).toEqual([]);
    });

    test("keeps a row whose number is missing, as the website does, because only an exact 0 is skipped", () => {
        const result = selectDistrictVotes([scoreRow(null, "Unnumbered", null, 1, 0)], []);
        expect(result.rows).toHaveLength(1);
        expect(result.rows[0].label).toBe("District Unnumbered");
        expect(result.rows[0].number).toBe(0);
    });

    test("two districts with the same number but different region codes stay separate rows with separate keys", () => {
        const result = selectDistrictVotes([scoreRow(3, "3A", "A", 1, 0), scoreRow(3, "3B", "B", 0, 1)], []);
        expect(result.rows).toHaveLength(2);
        expect(new Set(result.rows.map((r) => r.key)).size).toBe(2);
    });

    describe("the reader's districts", () => {
        const rows = [scoreRow(2, "MD2", "MD", 3, 4), scoreRow(3, "3A", "A", 9, 1), scoreRow(3, "3B", "B", 0, 6)];

        test("match on number and region code, not number alone", () => {
            const result = selectDistrictVotes(rows, [READER]);
            expect(result.readerRows).toHaveLength(1);
            expect(result.readerRows[0]).toMatchObject({ forPct: 9, againstPct: 1, isReaderDistrict: true });
            expect(result.rows.filter((r) => r.isReaderDistrict)).toHaveLength(1);
            expect(result.rows.find((r) => r.forPct === 0 && r.againstPct === 6)?.isReaderDistrict).toBe(false);
        });

        test("fall back to the name when either side has no region code", () => {
            const result = selectDistrictVotes(
                [scoreRow(3, "3A", null, 9, 1)],
                [{ name: "3A", number: 3, region_code: "A" }],
            );
            expect(result.readerRows).toHaveLength(1);
            expect(result.readerRows[0].forPct).toBe(9);
        });

        test("a signed-out reader gets only the at-large district, so there is no reader row", () => {
            const result = selectDistrictVotes(rows, [{ name: "MD0", number: 0, region_code: "MD" }]);
            expect(result.readerRows).toEqual([]);
            expect(result.rows.some((r) => r.isReaderDistrict)).toBe(false);
        });

        test("a reader district the bill has no score row for becomes a zero row for the reader panel only", () => {
            const result = selectDistrictVotes(rows, [{ name: "MD7", number: 7, region_code: "MD" }]);
            expect(result.readerRows).toHaveLength(1);
            expect(result.readerRows[0]).toMatchObject({
                label: "District 7",
                forPct: 0,
                againstPct: 0,
                suppressed: true,
                net: 0,
                isReaderDistrict: true,
            });
            expect(result.rows.map((r) => r.number)).toEqual([2, 3, 3]);
        });

        test("a repeated reader district yields one reader row", () => {
            const result = selectDistrictVotes(rows, [READER, { ...READER }]);
            expect(result.readerRows).toHaveLength(1);
        });

        test("missing reader districts leave the rows unmarked", () => {
            for (const input of [null, undefined, []]) {
                const result = selectDistrictVotes(rows, input);
                expect(result.readerRows).toEqual([]);
                expect(result.rows.some((r) => r.isReaderDistrict)).toBe(false);
            }
        });
    });
});

// @lat: [[district-chart-tooltip#The mobile bill JSON carries the names, the web page does not]]
describe("legislator names on a district row", () => {
    const withNames = (legislatorNames: unknown) =>
        selectDistrictVotes([{ ...scoreRow(1, "MD1", "MD", 4, 2), legislator_names: legislatorNames } as never], [])
            .rows[0];

    test("keeps the names in the order the server sent them", () => {
        expect(withNames(["Amy Adams", "Zed Zane"]).legislatorNames).toEqual(["Amy Adams", "Zed Zane"]);
    });

    test("trims each name and drops blanks and non-strings", () => {
        expect(withNames(["  Amy Adams ", "", "   ", null, 7]).legislatorNames).toEqual(["Amy Adams"]);
    });

    test("a missing, null or non-list value means nobody holds the district", () => {
        const [row] = selectDistrictVotes([scoreRow(1, "MD1", "MD", 4, 2)], []).rows;
        expect(row.legislatorNames).toEqual([]);
        for (const value of [undefined, null, "Amy Adams", 7, {}]) {
            expect(withNames(value).legislatorNames).toEqual([]);
        }
    });

    test("a reader district with no tally has no names", () => {
        const result = selectDistrictVotes(
            [scoreRow(1, "MD1", "MD", 4, 2)],
            [{ name: "MD7", number: 7, region_code: "MD" }],
        );
        expect(result.readerRows[0].legislatorNames).toEqual([]);
    });
});

describe("representativesText", () => {
    test("says Representative for one name, as the website tooltip does", () => {
        expect(representativesText({ legislatorNames: ["Jane Doe"] })).toBe("Representative: Jane Doe");
    });

    test("says Representatives and joins with a comma for several names", () => {
        expect(representativesText({ legislatorNames: ["Amy Adams", "Zed Zane"] })).toBe(
            "Representatives: Amy Adams, Zed Zane",
        );
    });

    test("is null when nobody holds the district", () => {
        expect(representativesText({ legislatorNames: [] })).toBeNull();
    });
});

// @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
describe("ten-voter minimum", () => {
    const district = (number: number) => ({ name: `MD${number}`, number, region_code: "MD" });
    const shown = (number: number, forPercent: number) => ({
        district: district(number),
        comparison_suppressed: false,
        for_percent: forPercent,
        against_percent: 100 - forPercent,
        at_large: false,
    });

    test("a bill score with no flag, or a suppressed one, is suppressed", () => {
        expect(isVoteComparisonSuppressed({ for: 40, against: 2 })).toBe(true);
        expect(isVoteComparisonSuppressed({ comparison_suppressed: true })).toBe(true);
        expect(isVoteComparisonSuppressed(null)).toBe(true);
        expect(isVoteComparisonSuppressed({ for: 7, against: 3, comparison_suppressed: false })).toBe(false);
    });

    test("rows carry percentages and no counts", () => {
        const { rows } = selectDistrictVotes([shown(4, 75)], []);

        expect(rows).toHaveLength(1);
        expect(rows[0]).toMatchObject({ number: 4, forPct: 75, againstPct: 25, net: 50, suppressed: false });
        expect(rows[0]).not.toHaveProperty("forCount");
        expect(rows[0]).not.toHaveProperty("total");
    });

    test("a suppressed district, a district with no flag and the at-large district are not drawn", () => {
        const { rows } = selectDistrictVotes(
            [
                shown(4, 75),
                { district: district(7), comparison_suppressed: true, for_percent: null, against_percent: null },
                { district: district(8), for: 9, against: 3 } as never,
                { ...shown(9, 60), at_large: true },
                shown(0, 60),
            ],
            [],
        );

        expect(rows.map((row) => row.number)).toEqual([4]);
    });

    test("the reader's district is a suppressed row when it is hidden or absent", () => {
        const { rows, readerRows } = selectDistrictVotes(
            [
                shown(4, 75),
                { district: district(7), comparison_suppressed: true, for_percent: null, against_percent: null },
            ],
            [district(7), district(11)],
        );

        expect(rows.map((row) => row.number)).toEqual([4]);
        expect(readerRows.map((row) => [row.number, row.suppressed])).toEqual([
            [7, true],
            [11, true],
        ]);
        expect(readerRows.map(districtMajority)).toEqual([null, null]);
    });

    test("the majority comes from the percentages", () => {
        const [forRow, againstRow, tieRow] = selectDistrictVotes([shown(1, 75), shown(2, 40), shown(3, 50)], []).rows;

        expect([forRow, againstRow, tieRow].map(districtMajority)).toEqual(["for", "against", "tie"]);
    });
});
