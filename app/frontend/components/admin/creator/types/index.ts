import { ISelectOption, KeyOf, sway } from "sway";
import type { ISourceUseInput, NewsUsage } from "app/frontend/types/bill_creator";

export interface IFieldProps<T> {
    swayField: sway.IFormField<T>;
    onBlur?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
    fieldGroupLength: number;
}

// @lat: [[bills-category-filter#Bills category filter#The single-subject category column is retired]]
export interface IApiBillCreator extends Omit<
    sway.IApiBill,
    | "chamber"
    | "category"
    | "status"
    | "summary"
    | "legislator_id"
    | "sway_locale_id"
    | "scheduled_release_date_utc"
    | "introduced_date_time_utc"
    | "withdrawn_date_time_utc"
    | "house_vote_date_time_utc"
    | "senate_vote_date_time_utc"
> {
    // @lat: [[bill-creator-form-type-contract#chamber]]
    chamber: sway.IApiBill["chamber"] | ISelectOption | null;
    status: sway.IApiBill["status"] | ISelectOption;
    // @lat: [[bill-creator-form-type-contract#summary]]
    summary: string;
    news_usage?: NewsUsage;
    source_uses?: ISourceUseInput[];
    // @lat: [[bill-creator-form-type-contract#chamber]]
    legislator_id: sway.IApiBill["legislator_id"] | ISelectOption | null;
    house_roll_call_vote_number: string | number;
    senate_roll_call_vote_number: string | number;
    // @lat: [[use-locale-hook-contract#swayLocaleId in the Bill Creator form]]
    sway_locale_id: number | undefined;
    // @lat: [[bill-creator-form-type-contract#scheduled_release_date_utc]]
    scheduled_release_date_utc?: string;
    // @lat: [[bill-creator-form-type-contract#introduced_date_time_utc, withdrawn_date_time_utc, house_vote_date_time_utc, senate_vote_date_time_utc]]
    introduced_date_time_utc: Date | string | null;
    withdrawn_date_time_utc: Date | string | null;
    house_vote_date_time_utc: Date | string | null;
    senate_vote_date_time_utc: Date | string | null;
}

// @lat: [[bill-creator-form-type-contract#IApiLegislatorVote]]
export type IApiLegislatorVote = {
    legislator_id: number;
    support: sway.TLegislatorSupport;
};

export interface ICreatorLegislatorVotes {
    FOR: IApiLegislatorVote[];
    AGAINST: IApiLegislatorVote[];
    ABSTAIN: IApiLegislatorVote[];
}

export type TOrganizationOption = ISelectOption & {
    summary: string;
    support: sway.TUserSupport | "ABSTAIN";
    icon_url?: string;
    icon_signed_id?: string;
    position_id?: number;
};

export type TOrganizationError = Record<KeyOf<TOrganizationOption>, string> | undefined;
export interface IOrganizationErrors {
    organizations: TOrganizationError[];
}

export interface ICreatorOrganizations {
    bill_id: number;
    organizations: TOrganizationOption[];
}
