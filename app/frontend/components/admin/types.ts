import { ISelectOption, sway } from "sway";

export type TOrganizationOption = ISelectOption & { summary: string; iconPath?: string }

export type ISubmitValues = sway.IBill & {
    legislator: ISelectOption;

    supporters: ISelectOption[];
    opposers: ISelectOption[];
    abstainers: ISelectOption[];

    category: ISelectOption;
    status: ISelectOption;

    // organizations: IDataOrganizationPosition[];

    swayAudioBucketPath?: string;
    swayAudioByline?: string;

    organizationsSupport: TOrganizationOption[];
    organizationsOppose: TOrganizationOption[];
};
