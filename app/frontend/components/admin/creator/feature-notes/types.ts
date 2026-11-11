export interface IFeatureNote {
    feature: string;
    note: string;
}

export type TFeatureNoteGroup = Record<string, IFeatureNote>;
