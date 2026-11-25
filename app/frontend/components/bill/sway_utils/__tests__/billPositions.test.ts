import { describe, expect, it } from "vitest";
import type { sway } from "sway";

import { Support } from "app/frontend/sway_constants";
import {
    isVoteComparisonSuppressed,
    selectBillPositions,
    selectDistrictVoteSplits,
    selectVoteMajority,
    selectVoteTally,
} from "app/frontend/components/bill/sway_utils/billPositions";

// A flat org-bill-position row shaped the way Bill#render sends it over the
// wire (built by OrganizationBillPosition#to_builder): the organization is
// embedded right alongside its stance and summary for one bill.
const billPosition = (
    id: number,
    bill_id: number,
    orgName: string,
    support: string,
    summary: string,
): sway.IBillOrganizationPosition => ({
    id,
    bill_id,
    support,
    summary,
    organization: { id, sway_locale_id: 1, name: orgName },
    origin: "Org-posted",
    origin_url: null,
});

describe("selectBillPositions", () => {
    const sierra = billPosition(10, 100, "Sierra Club", Support.For, "Protects the watershed.");
    const chamber = billPosition(20, 100, "Chamber of Commerce", Support.Against, "Raises costs.");
    const abstainer = billPosition(30, 100, "Neutral Org", Support.Abstain, "No firm stance.");
    const noSummary = billPosition(40, 100, "Quiet Org", Support.For, "");
    const otherBill = billPosition(50, 999, "Offtopic Org", Support.For, "About another bill.");

    it("collects every position with a summary into all", () => {
        const { all } = selectBillPositions([sierra, chamber, abstainer], 100);
        expect(all.map(({ org }) => org.name)).toEqual(["Sierra Club", "Chamber of Commerce", "Neutral Org"]);
    });

    it("excludes positions with an empty summary", () => {
        const { all } = selectBillPositions([sierra, noSummary], 100);
        expect(all.map(({ org }) => org.name)).toEqual(["Sierra Club"]);
    });

    it("excludes positions on a different bill (defensive bill_id guard)", () => {
        const { all } = selectBillPositions([sierra, otherBill], 100);
        expect(all.map(({ org }) => org.name)).toEqual(["Sierra Club"]);
    });

    it("splits supporting and opposing by stance", () => {
        const { supporting, opposing } = selectBillPositions([sierra, chamber, abstainer], 100);
        expect(supporting.map(({ org }) => org.name)).toEqual(["Sierra Club"]);
        expect(opposing.map(({ org }) => org.name)).toEqual(["Chamber of Commerce"]);
    });

    it("keeps abstain positions in all but out of supporting and opposing", () => {
        const { all, supporting, opposing } = selectBillPositions([abstainer], 100);
        expect(all).toHaveLength(1);
        expect(supporting).toHaveLength(0);
        expect(opposing).toHaveLength(0);
    });

    it("returns empty arrays when positions is undefined", () => {
        expect(selectBillPositions(undefined, 100)).toEqual({ all: [], supporting: [], opposing: [] });
    });
});

describe("selectVoteTally", () => {
    it("reads the published For and Against percentages", () => {
        expect(selectVoteTally({ for_percent: 70, against_percent: 30 })).toEqual({
            forPercent: 70,
            againstPercent: 30,
        });
    });

    it("returns zeros for a null score", () => {
        expect(selectVoteTally(null)).toEqual({ forPercent: 0, againstPercent: 0 });
    });

    it("returns zeros for an undefined score", () => {
        expect(selectVoteTally(undefined)).toEqual({ forPercent: 0, againstPercent: 0 });
    });

    it("returns zeros for a withheld score whose percentages are null", () => {
        expect(selectVoteTally({ for_percent: null, against_percent: null })).toEqual({
            forPercent: 0,
            againstPercent: 0,
        });
    });
});

describe("selectVoteMajority", () => {
    const vote = (support: string): sway.IUserVote => ({ support }) as sway.IUserVote;
    const tally = (for_percent: number, against_percent: number) => selectVoteTally({ for_percent, against_percent });

    it("reports 'No votes yet' with no verdict when the tally is empty", () => {
        const r = selectVoteMajority(vote(Support.For), tally(0, 0));
        expect(r.majorityStatus).toBe("No votes yet");
        expect(r.withMajority).toBeNull();
        expect(r.userVoted).toBe(true);
    });

    it("reports 'Evenly split' with no verdict on equal rounded percentages", () => {
        const r = selectVoteMajority(vote(Support.For), tally(50, 50));
        expect(r.majorityStatus).toBe("Evenly split");
        expect(r.withMajority).toBeNull();
    });

    it("sets withMajority true when the user voted with the leading side", () => {
        const r = selectVoteMajority(vote(Support.For), tally(70, 30));
        expect(r.majorityStatus).toBe("For leading");
        expect(r.userSupports).toBe(true);
        expect(r.withMajority).toBe(true);
    });

    it("sets withMajority false when the user voted against the leading side", () => {
        const r = selectVoteMajority(vote(Support.For), tally(30, 70));
        expect(r.majorityStatus).toBe("Against leading");
        expect(r.withMajority).toBe(false);
    });

    it("sets withMajority true when Against votes lead", () => {
        const r = selectVoteMajority(vote(Support.Against), tally(30, 70));
        expect(r.userSupports).toBe(false);
        expect(r.withMajority).toBe(true);
    });

    it("reports no verdict and userVoted false when the user has not voted", () => {
        const r = selectVoteMajority(undefined, tally(70, 30));
        expect(r.userVoted).toBe(false);
        expect(r.userSupports).toBe(false);
        expect(r.withMajority).toBeNull();
    });
});

const district = (number: number): sway.IDistrict =>
    ({ name: `D-${number}`, number, region_code: "D" }) as sway.IDistrict;

const billScore = (overrides: Partial<sway.IBillScore>): sway.IBillScore => ({
    bill_id: 1,
    for: 18,
    against: 12,
    for_percent: 60,
    against_percent: 40,
    comparison_suppressed: false,
    voters_needed: 0,
    districts: [],
    ...overrides,
});

// @lat: [[voter-privacy-threshold#The web bill page asks one helper whether to draw a comparison]]
describe("isVoteComparisonSuppressed", () => {
    it("is true when the server says the tally is suppressed", () => {
        expect(isVoteComparisonSuppressed(billScore({ comparison_suppressed: true, voters_needed: 4 }))).toBe(true);
    });

    it("is false only when the server says the tally may be shown", () => {
        expect(isVoteComparisonSuppressed(billScore({ comparison_suppressed: false }))).toBe(false);
    });

    it("is true when there is no score or no flag", () => {
        expect(isVoteComparisonSuppressed(undefined)).toBe(true);
        expect(isVoteComparisonSuppressed(null)).toBe(true);
        expect(isVoteComparisonSuppressed({ for: 40, against: 2 } as unknown as sway.IBillScore)).toBe(true);
    });
});

describe("selectDistrictVoteSplits", () => {
    const score = billScore({
        districts: [
            {
                district: district(7),
                comparison_suppressed: false,
                for_percent: 40,
                against_percent: 60,
                at_large: false,
            },
            {
                district: district(0),
                comparison_suppressed: false,
                for_percent: 60,
                against_percent: 40,
                at_large: true,
            },
            {
                district: district(4),
                comparison_suppressed: false,
                for_percent: 75,
                against_percent: 25,
                at_large: false,
            },
            {
                district: district(2),
                comparison_suppressed: true,
                for_percent: null,
                against_percent: null,
                at_large: false,
            },
        ],
    });

    it("keeps districts that carry percentages, in district order", () => {
        expect(
            selectDistrictVoteSplits(score).map((split) => [
                split.district.number,
                split.forPercent,
                split.againstPercent,
            ]),
        ).toEqual([
            [4, 75, 25],
            [7, 40, 60],
        ]);
    });

    it("drops suppressed districts and the at-large district", () => {
        const numbers = selectDistrictVoteSplits(score).map((split) => split.district.number);
        expect(numbers).not.toContain(2);
        expect(numbers).not.toContain(0);
    });

    it("returns nothing when the bill tally itself is suppressed", () => {
        expect(selectDistrictVoteSplits({ ...score, comparison_suppressed: true })).toEqual([]);
        expect(selectDistrictVoteSplits(undefined)).toEqual([]);
    });
});
