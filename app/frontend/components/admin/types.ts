import { ISelectOption, sway } from "sway";

export type TOrganizationOption = ISelectOption & { summary: string; iconPath?: string };

export type ISubmitValues = sway.IBill & {
    legislator: ISelectOption;

    supporters: ISelectOption[];
    opposers: ISelectOption[];
    abstainers: ISelectOption[];

    category: ISelectOption;
    status: ISelectOption;

    // organizations: IDataOrganizationPosition[];

    audioBucketPath?: string;
    audioByLine?: string;

    organizationsSupport: TOrganizationOption[];
    organizationsOppose: TOrganizationOption[];
};
