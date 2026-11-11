import { IApiLegislatorVote } from "app/frontend/components/admin/creator/types";
import { Support, type TSupport } from "app/frontend/sway_constants";
import { titleize } from "app/frontend/sway_utils";
import { sway } from "sway";

export const LEDGER_COLUMNS: { key: TSupport; label: string }[] = [
    { key: Support.For, label: "For" },
    { key: Support.Against, label: "Against" },
    { key: Support.Abstain, label: "Abstain" },
];

export const toApiLegislatorVote = (legislator_vote: sway.ILegislatorVote): IApiLegislatorVote => ({
    legislator_id: legislator_vote.legislator_id,
    support: legislator_vote.support,
});

export const filterOut = (votes: IApiLegislatorVote[], legislator_id: number) =>
    votes.filter((v) => v.legislator_id !== legislator_id);

export const legislatorDisplayName = (l: sway.ILegislator) => `${titleize(l.first_name)} ${titleize(l.last_name)}`;
