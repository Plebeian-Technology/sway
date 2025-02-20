import { ISelectOption, sway } from "sway";

export interface ISubmitValues {
    bill: Omit<
        sway.IBill,
        | "category"
        | "chamber"
        | "status"
        | "active"
        | "scheduled_release_date_utc"
        | "vote_date_time_utc"
        | "vote"
        | "introduced_date_time_utc"
        | "withdrawn_date_time_utc"
        | "house_vote_date_time_utc"
        | "senate_vote_date_time_utc"
    > & {
        summaryPreview: string;
    } & {
        chamber: string | ISelectOption;
    } & {
        vote: Omit<sway.IVote, "id">;
    } & {
        category: sway.TBillCategory | ISelectOption;
        status: sway.TBillStatus | ISelectOption;
    } & {
        introduced_date_time_utc: string | null;
        withdrawn_date_time_utc: string | null;
        house_vote_date_time_utc: string | null;
        senate_vote_date_time_utc: string | null;
    };
    sponsor: sway.ILegislator | ISelectOption | null;
}
