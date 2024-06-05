import { ISelectOption, sway } from "sway";

export type TOrganizationOption = ISelectOption & { summary: string; iconPath?: string };

export type ISubmitValues = sway.IBill & {
    legislator: ISelectOption;

    supporters: ISelectOption[];
    opposers: ISelectOption[];
    abstainers: ISelectOption[];

    category: ISelectOption;
    status: ISelectOption;
    chamber: ISelectOption;

    // organizations: IDataOrganizationPosition[];

    audioBucketPath?: string;
    audioByLine?: string;

    houseRollCallVoteNumber?: number;
    senateRollCallVoteNumber?: number;

    organizationsSupport: TOrganizationOption[];
    organizationsOppose: TOrganizationOption[];
};
