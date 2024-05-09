import { ISelectOption, sway } from "sway";

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

    organizationsSupport: (ISelectOption & { summary: string })[];
    organizationsOppose: (ISelectOption & { summary: string })[];
};
