export type TFeedItemKind =
    | "bill_of_the_month_released"
    | "legislator_voted"
    | "organization_position_taken"
    | "user_joined"
    | "representatives_found"
    | "legislative_term_began";

export type TFeedSupport = "FOR" | "AGAINST" | "ABSTAIN";
export type TFeedAgreement = "agree" | "differ";

export interface IFeedLocale {
    id: number;
    name: string;
}

export interface IFeedBill {
    id: number;
    external_id: string;
    title: string;
    summary: string | null;
    summary_ai_unreviewed: boolean;
    vote_count: number;
    view_count: number;
    share_count: number;
}

export interface IFeedLegislator {
    id: number;
    full_name: string;
    title: string | null;
    district_name: string | null;
    photo_url: string | null;
}

export interface IFeedOrganization {
    id: number;
    name: string;
    support: string;
}

export interface IFeedItem {
    key: string;
    kind: TFeedItemKind;
    occurred_at: string;
    sway_locale: IFeedLocale | null;
    bill: IFeedBill | null;
    legislator: IFeedLegislator | null;
    legislators: IFeedLegislator[];
    organization: IFeedOrganization | null;
    user_support: TFeedSupport | null;
    legislator_support: TFeedSupport | null;
    agreement: TFeedAgreement | null;
}
