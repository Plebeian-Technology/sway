import { ISelectOption, sway } from "sway";

export interface ISubmitValues {
    bill: Omit<
        sway.IBill,
        | "category"
        | "chamber"
        | "status"
        | "active"
        | "scheduledReleaseDateUtc"
        | "voteDateTimeUtc"
        | "vote"
        | "introducedDateTimeUtc"
        | "withdrawnDateTimeUtc"
        | "houseVoteDateTimeUtc"
        | "senateVoteDateTimeUtc"
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
        introducedDateTimeUtc: string | null;
        withdrawnDateTimeUtc: string | null;
        houseVoteDateTimeUtc: string | null;
        senateVoteDateTimeUtc: string | null;
    };
    sponsor: sway.ILegislator | ISelectOption | null;
}
