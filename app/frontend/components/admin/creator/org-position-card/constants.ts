import type { TSupport } from "app/frontend/sway_constants";

// @lat: [[org-position-card-editing-and-approval-ui#Why SUPPORT_LABEL says "Neutral", not "Abstain"]]
export type TOrganizationPositionSupport = "support" | "oppose" | "neutral";
export type TStance = TOrganizationPositionSupport;

export const SUPPORT_TO_TONE: Record<TSupport, "success" | "danger" | "warning"> = {
    FOR: "success",
    AGAINST: "danger",
    ABSTAIN: "warning",
};

// @lat: [[org-position-card-editing-and-approval-ui#Why SUPPORT_LABEL says "Neutral", not "Abstain"]]
export const SUPPORT_LABEL: Record<TSupport, string> = {
    FOR: "Support",
    AGAINST: "Oppose",
    ABSTAIN: "Neutral",
};

export const POSITION_SUPPORT_TO_VOTE_SUPPORT: Record<TOrganizationPositionSupport, TSupport> = {
    support: "FOR",
    oppose: "AGAINST",
    neutral: "ABSTAIN",
};
export const STANCE_TO_SUPPORT: Record<TStance, TSupport> = POSITION_SUPPORT_TO_VOTE_SUPPORT;

export const POSITION_SUPPORT_OPTIONS: ReadonlyArray<{ value: TOrganizationPositionSupport; label: string }> = [
    { value: "support", label: "Support" },
    { value: "oppose", label: "Oppose" },
    { value: "neutral", label: "Neutral" },
];
export const STANCE_OPTIONS: ReadonlyArray<{ value: TStance; label: string }> = POSITION_SUPPORT_OPTIONS;
