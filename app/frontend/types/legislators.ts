import { sway } from "sway";

// @lat: [[current-legislator-term#Which term a legislator is serving now#Planned automatic legislator updates#Historical repair explanations]]
export interface IHistoricalScoreExplanation {
    title: string;
    body: string;
    delta: number | null;
    score_type: string;
}

// @lat: [[legislator-history-serialization#Read-only historical term agreement serialization]]
export interface ILegislatorTermEntry {
    id: number;
    session_label: string;
    term_start_year: number;
    term_end_year: number;
    began_on: string | null;
    ended_on: string | null;
    district_name: string | null;
    is_executive: boolean;
    active: boolean;
    district_score: sway.scoring.IAgreeable | null;
    locale_score: sway.scoring.IAgreeable | null;
    user_score: sway.scoring.IAgreeable | null;
    correction_explanation: IHistoricalScoreExplanation | null;
}

// @lat: [[legislator-botm-record#Bill of the Month voting record on the legislator page]]
export interface ILegislatorBillOfTheMonthVote {
    bill_id: number;
    external_id: string;
    title: string;
    scheduled_release_date_utc: string;
    status: string | null;
    legislator_vote: "FOR" | "AGAINST" | "ABSTAIN" | null;
    user_vote: "FOR" | "AGAINST" | null;
    alignment: "agreed" | "disagreed" | null;
}

export interface ILegislatorWithTerms extends sway.ILegislator {
    terms?: ILegislatorTermEntry[];
    bill_of_the_month_votes?: ILegislatorBillOfTheMonthVote[];
}

export interface ILegislatorShowProps {
    legislator: ILegislatorWithTerms;
}

export interface ILegislatorHistoryTermsPanelProps {
    legislator: sway.ILegislator;
    terms?: ILegislatorTermEntry[];
}

export interface ILegislatorTermCardProps {
    term: ILegislatorTermEntry;
    legislator: sway.ILegislator;
}

export interface IHistoricalRepairModalProps {
    explanation: IHistoricalScoreExplanation;
    term: ILegislatorTermEntry;
    legislator: sway.ILegislator;
    open: boolean;
    onOpenChange: (open: boolean) => void;
}
