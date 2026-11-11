import type { ComponentType } from "react";
import type { sway } from "sway";

// @lat: [[client-caches-and-identity#Bill refresh feedback]]
export interface BillLayoutProps {
    bill: sway.IBill;
    sponsor: sway.ILegislator;
    organizations: sway.IBillOrganizationPosition[];
    user_vote?: sway.IUserVote;
    bill_score?: sway.IBillScore;
    isAwaitingScoreUpdate: boolean;
}

export type BillLayout = ComponentType<BillLayoutProps>;
