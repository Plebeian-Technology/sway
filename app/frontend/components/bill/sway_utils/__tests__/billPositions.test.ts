import { describe, expect, it } from "vitest";
import type { sway } from "sway";

import { Support } from "app/frontend/sway_constants";
import {
    selectBillPositions,
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
    it("computes counts, total, and rounded support percentage", () => {
        expect(selectVoteTally({ for: 30, against: 10 })).toEqual({
            forCount: 30,
            againstCount: 10,
            total: 40,
            forPct: 75,
        });
    });

    it("rounds the support percentage to the nearest whole number", () => {
        expect(selectVoteTally({ for: 1, against: 2 }).forPct).toBe(33);
    });

    it("returns all zeros for a null score", () => {
        expect(selectVoteTally(null)).toEqual({ forCount: 0, againstCount: 0, total: 0, forPct: 0 });
    });

    it("returns all zeros for an undefined score", () => {
        expect(selectVoteTally(undefined)).toEqual({ forCount: 0, againstCount: 0, total: 0, forPct: 0 });
    });

    it("yields a 0 percentage when no votes are cast, without dividing by zero", () => {
        expect(selectVoteTally({ for: 0, against: 0 }).forPct).toBe(0);
    });
});

describe("selectVoteMajority", () => {
    const vote = (support: string): sway.IUserVote => ({ support }) as sway.IUserVote;

    it("reports 'No votes yet' with no verdict when the tally is empty", () => {
        const r = selectVoteMajority(vote(Support.For), selectVoteTally({ for: 0, against: 0 }));
        expect(r.majorityStatus).toBe("No votes yet");
        expect(r.withMajority).toBeNull();
        expect(r.userVoted).toBe(true);
    });

    it("reports 'Evenly split' with no verdict on a tie", () => {
        const r = selectVoteMajority(vote(Support.For), selectVoteTally({ for: 10, against: 10 }));
        expect(r.majorityStatus).toBe("Evenly split");
        expect(r.withMajority).toBeNull();
    });

    it("sets withMajority true when the user voted with the leading side", () => {
        const r = selectVoteMajority(vote(Support.For), selectVoteTally({ for: 30, against: 10 }));
        expect(r.majorityStatus).toBe("For leading");
        expect(r.userSupports).toBe(true);
        expect(r.withMajority).toBe(true);
    });

    it("sets withMajority false when the user voted against the leading side", () => {
        const r = selectVoteMajority(vote(Support.For), selectVoteTally({ for: 10, against: 30 }));
        expect(r.majorityStatus).toBe("Against leading");
        expect(r.withMajority).toBe(false);
    });

    it("sets withMajority true when Against votes lead", () => {
        const r = selectVoteMajority(vote(Support.Against), selectVoteTally({ for: 10, against: 30 }));
        expect(r.userSupports).toBe(false);
        expect(r.withMajority).toBe(true);
    });

    it("reports no verdict and userVoted false when the user has not voted", () => {
        const r = selectVoteMajority(undefined, selectVoteTally({ for: 30, against: 10 }));
        expect(r.userVoted).toBe(false);
        expect(r.userSupports).toBe(false);
        expect(r.withMajority).toBeNull();
    });
});
