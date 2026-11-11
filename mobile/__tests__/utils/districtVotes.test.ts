// @lat: [[mobile-bill-surface-components-design#DistrictVotesPanel]]
import {
    districtMajority,
    formatVoteCount,
    representativesText,
    selectDistrictVotes,
} from "../../src/utils/districtVotes";

// Rows in the shape BillScoreDistrictResource sends: no district id, region_code beside name and number.
const scoreRow = (
    number: number | null,
    name: string,
    regionCode: string | null,
    forCount: number | string | null,
    againstCount: number | string | null,
) => ({
    bill_score_id: 9,
    district: { name, number, region_code: regionCode },
    for: forCount,
    against: againstCount,
});

const READER = { name: "3A", number: 3, region_code: "A" };

describe("selectDistrictVotes", () => {
    test("returns nothing for a missing or empty district list", () => {
        for (const input of [null, undefined, []]) {
            const result = selectDistrictVotes(input, []);
            expect(result.rows).toEqual([]);
            expect(result.readerRows).toEqual([]);
            expect(result.hasVotes).toBe(false);
            expect(result.maxVotes).toBe(0);
            expect(result.maxAbsNet).toBe(0);
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
        expect(result.hasVotes).toBe(false);
    });

    test("keeps a row whose number is missing, as the website does, because only an exact 0 is skipped", () => {
        const result = selectDistrictVotes([scoreRow(null, "Unnumbered", null, 1, 0)], []);
        expect(result.rows).toHaveLength(1);
        expect(result.rows[0].label).toBe("District Unnumbered");
        expect(result.rows[0].number).toBe(0);
    });

    test("computes for, against, total, net and the for percentage per district", () => {
        const [row] = selectDistrictVotes([scoreRow(4, "MD4", "MD", 12, 8)], []).rows;
        expect(row).toMatchObject({
            label: "District 4",
            number: 4,
            name: "MD4",
            forCount: 12,
            againstCount: 8,
            total: 20,
            net: 4,
            forPct: 60,
            isReaderDistrict: false,
        });
    });

    test("net is not clamped and goes negative when against leads", () => {
        const [row] = selectDistrictVotes([scoreRow(1, "MD1", "MD", 2, 9)], []).rows;
        expect(row.net).toBe(-7);
    });

    test("coerces strings and nulls the way the website does", () => {
        const [row] = selectDistrictVotes([scoreRow(1, "MD1", "MD", "7", null)], []).rows;
        expect(row.forCount).toBe(7);
        expect(row.againstCount).toBe(0);
        expect(row.net).toBe(7);
    });

    test("an unparseable count counts as zero instead of poisoning the chart with NaN", () => {
        const [row] = selectDistrictVotes([scoreRow(1, "MD1", "MD", "n/a", 3)], []).rows;
        expect(row.forCount).toBe(0);
        expect(row.net).toBe(-3);
    });

    test("the by-district scale is the largest single for or against count, not a total", () => {
        const result = selectDistrictVotes([scoreRow(1, "MD1", "MD", 10, 10), scoreRow(2, "MD2", "MD", 3, 25)], []);
        expect(result.maxVotes).toBe(25);
    });

    test("the net scale is the largest absolute for-minus-against", () => {
        const result = selectDistrictVotes([scoreRow(1, "MD1", "MD", 10, 4), scoreRow(2, "MD2", "MD", 3, 25)], []);
        expect(result.maxAbsNet).toBe(22);
    });

    test("hasVotes is false when every district is at zero and true once any district has a vote", () => {
        const zero = selectDistrictVotes([scoreRow(1, "MD1", "MD", 0, 0)], []);
        expect(zero.rows).toHaveLength(1);
        expect(zero.hasVotes).toBe(false);

        const some = selectDistrictVotes([scoreRow(1, "MD1", "MD", 0, 0), scoreRow(2, "MD2", "MD", 0, 1)], []);
        expect(some.hasVotes).toBe(true);
    });

    test("perfectly tied districts have votes but no net scale", () => {
        const result = selectDistrictVotes([scoreRow(1, "MD1", "MD", 5, 5)], []);
        expect(result.hasVotes).toBe(true);
        expect(result.maxAbsNet).toBe(0);
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
            expect(result.readerRows[0]).toMatchObject({ forCount: 9, againstCount: 1, isReaderDistrict: true });
            expect(result.rows.filter((r) => r.isReaderDistrict)).toHaveLength(1);
            expect(result.rows.find((r) => r.forCount === 0 && r.againstCount === 6)?.isReaderDistrict).toBe(false);
        });

        test("fall back to the name when either side has no region code", () => {
            const result = selectDistrictVotes(
                [scoreRow(3, "3A", null, 9, 1)],
                [{ name: "3A", number: 3, region_code: "A" }],
            );
            expect(result.readerRows).toHaveLength(1);
            expect(result.readerRows[0].forCount).toBe(9);
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
                forCount: 0,
                againstCount: 0,
                total: 0,
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

describe("districtMajority", () => {
    const row = (forCount: number, againstCount: number) =>
        selectDistrictVotes([scoreRow(1, "MD1", "MD", forCount, againstCount)], []).rows[0];

    test("names the side with more votes", () => {
        expect(districtMajority(row(5, 2))).toBe("for");
        expect(districtMajority(row(2, 5))).toBe("against");
    });

    test("is a tie when the sides are level and null when nobody voted", () => {
        expect(districtMajority(row(4, 4))).toBe("tie");
        expect(districtMajority(row(0, 0))).toBeNull();
    });
});

describe("formatVoteCount", () => {
    test("groups thousands", () => {
        expect(formatVoteCount(1234)).toBe("1,234");
        expect(formatVoteCount(42)).toBe("42");
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
