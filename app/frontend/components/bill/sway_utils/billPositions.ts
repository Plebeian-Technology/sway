import type { sway } from "sway";

import { Support } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

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

// @lat: [[voter-privacy-threshold#The web bill page asks one helper whether to draw a comparison]]
export const isVoteComparisonSuppressed = (
    billScore: Pick<sway.IBaseScore, "comparison_suppressed"> | null | undefined,
): boolean => billScore?.comparison_suppressed !== false;

// @lat: [[voter-privacy-threshold#Bill lists print one line for a hidden tally]]
export const suppressedVoteComparisonLine = (
    billScore: Pick<sway.IBaseScore, "voters_needed"> | null | undefined,
): string => {
    const votersNeeded = billScore?.voters_needed;
    return typeof votersNeeded === "number" && votersNeeded > 0
        ? PARITY_COPY.bill.voteComparisonPlaceholder.votersNeeded(votersNeeded)
        : PARITY_COPY.bill.voteComparisonPlaceholder.notEnoughVotes;
};

export interface DistrictVoteSplit {
    district: sway.IDistrict;
    forPercent: number;
    againstPercent: number;
}

// @lat: [[voter-privacy-threshold#Districts are sent as percentages only]]
export const selectDistrictVoteSplits = (billScore: sway.IBillScore | null | undefined): DistrictVoteSplit[] => {
    if (!billScore || isVoteComparisonSuppressed(billScore)) return [];

    return (billScore.districts ?? [])
        .flatMap((row) =>
            row.comparison_suppressed || row.at_large || row.for_percent === null || row.against_percent === null
                ? []
                : [{ district: row.district, forPercent: row.for_percent, againstPercent: row.against_percent }],
        )
        .sort((a, b) => a.district.number - b.district.number);
};

export const selectVoteTally = (billScore: Pick<sway.IBaseScore, "for" | "against"> | null | undefined): VoteTally => {
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
