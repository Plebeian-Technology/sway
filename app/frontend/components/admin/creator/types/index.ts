import { ISelectOption, KeyOf, sway } from "sway";

export interface IFieldProps<T> {
    swayField: sway.IFormField<T>;
    onBlur?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
    fieldGroupLength: number;
}

export interface IApiBillCreator extends Omit<sway.IApiBill, "chamber" | "category" | "status" | "legislator_id"> {
    chamber: sway.IApiBill["chamber"] | ISelectOption;
    category: sway.IApiBill["category"] | ISelectOption;
    status: sway.IApiBill["status"] | ISelectOption;
    legislator_id: sway.IApiBill["legislator_id"] | ISelectOption;
    house_roll_call_vote_number: string | number;
    senate_roll_call_vote_number: string | number;
}

export interface IApiLegislatorVote {
    legislator_id: number;
    support: sway.TLegislatorSupport;
}

export interface ICreatorLegislatorVotes {
    FOR: IApiLegislatorVote[];
    AGAINST: IApiLegislatorVote[];
    ABSTAIN: IApiLegislatorVote[];
}

export type TOrganizationOption = ISelectOption & { summary: string; support: sway.TUserSupport; icon_path?: string };

export type TOrganizationError = Record<KeyOf<TOrganizationOption>, string> | undefined;
export interface IBillOrganizationErrors {
    bill_organizations: TOrganizationError[];
}

export interface ICreatorOrganizations {
    bill_id: number;
    bill_organizations: TOrganizationOption[];
}
