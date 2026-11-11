import type { sway } from "sway";

import { Support } from "app/frontend/sway_constants";

export interface BillOrgPosition {
    org: sway.IOrganizationBase;
    position: sway.IOrganizationPosition;
}

export interface BillPositions {
    all: BillOrgPosition[];
    supporting: BillOrgPosition[];
    opposing: BillOrgPosition[];
}

// @lat: [[bills-controller-design#BillsController design#The bill page returns active organization positions as flat rows]]
export const selectBillPositions = (
    positions: sway.IBillOrganizationPosition[] | undefined,
    billId: number,
): BillPositions => {
    const all = (positions ?? []).flatMap((position) =>
        position.bill_id === billId && position.summary ? [{ org: position.organization, position }] : [],
    );
    return {
        all,
        supporting: all.filter(({ position }) => position.support === Support.For),
        opposing: all.filter(({ position }) => position.support === Support.Against),
    };
};

export interface VoteTally {
    forCount: number;
    againstCount: number;
    total: number;
    forPct: number;
}

export const selectVoteTally = (billScore: sway.IBaseScore | null | undefined): VoteTally => {
    const forCount = billScore?.for ?? 0;
    const againstCount = billScore?.against ?? 0;
    const total = forCount + againstCount;
    return { forCount, againstCount, total, forPct: total > 0 ? Math.round((forCount / total) * 100) : 0 };
};

export type VoteMajorityStatus = "No votes yet" | "Evenly split" | "For leading" | "Against leading";

// @lat: [[vote-majority-vocabulary#Vote majority vocabulary#Replacement architecture#VoteMajorityResult interface]]
export interface VoteMajorityResult {
    userVoted: boolean;
    userSupports: boolean;
    majorityStatus: VoteMajorityStatus;
    withMajority: boolean | null;
}

// @lat: [[vote-majority-vocabulary#Vote majority vocabulary#Replacement architecture#selectVoteMajority helper]]
export const selectVoteMajority = (
    userVote: sway.IUserVote | null | undefined,
    tally: VoteTally,
): VoteMajorityResult => {
    const { forCount, againstCount, total } = tally;
    const userVoted = Boolean(userVote);
    const userSupports = userVote?.support === Support.For;
    const majorityStatus: VoteMajorityStatus =
        total === 0
            ? "No votes yet"
            : forCount === againstCount
              ? "Evenly split"
              : forCount > againstCount
                ? "For leading"
                : "Against leading";
    const withMajority =
        userVoted && total > 0 && forCount !== againstCount ? userSupports === forCount > againstCount : null;
    return { userVoted, userSupports, majorityStatus, withMajority };
};
