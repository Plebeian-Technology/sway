import { sway } from "sway";

export interface IChartChoiceComponentProps {
    scores: sway.IUserLegislatorScoreV2 | sway.IAggregatedBillLocaleScores;
    isEmptyScore: boolean;
    title: string;
    colors: {
        primary: string;
        secondary: string;
    };
}

export type TChartChoiceComponent = React.FC<IChartChoiceComponentProps>;

export interface IChartChoice {
    title: string;
    score: sway.IUserLegislatorScoreV2;
    Component: TChartChoiceComponent;
    colors: {
        primary: string;
        secondary: string;
    };
}

export interface IMobileChartChoice extends IChartChoice {
    label: string;
    Icon: React.FC<any>;
}

export interface IChartContainerProps {
    user: sway.IUser | undefined;
    legislator: sway.ILegislator;
    userLegislatorScore: sway.IUserLegislatorScoreV2 | null | undefined;
    localeScores: sway.IAggregatedBillLocaleScores | null | undefined;
    isLoading: boolean;
}
